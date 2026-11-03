"use strict";

const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const vscode = require("vscode");

const OWNER = "preflight";
const DEBOUNCE_MS = 500;
const PROVIDER_EXTENSIONS = ["JohnnyMorganz.luau-lsp", "JohnnyMorganz.stylua"];
const STYLUA_FORMAT_COMMAND = "preflight.styluaFormatDocument";
const STYLUA_CONFIG = "repo/config/luau/stylua/.stylua.toml";
const PROBLEMS_DIRECTORY = path.join("build", "run", "editor-problems");
const PROBLEMS_ENDPOINT = "endpoint.json";
const DIAGNOSTIC_PATTERN = /^(.*):(\d+):(\d+):(\d+)(?::(\d+))?: (error|warning|info): ([^:]+): (.*)$/;
const DIAGNOSTIC_PREFIX = "::diagnostic::";
const DIAGNOSTICS_SNAPSHOT_PREFIX = "::diagnostics::";
const PREFLIGHT_INPUTS = [
	"repo/ci/preflight/**",
	"repo/config/ci/preflight/**",
	"providers/**",
	"dependencies/lune/**",
	".vscode/preflight/**",
];

function isPreflightInput(relativePath) {
	const normalized = relativePath.split(path.sep).join("/");
	return PREFLIGHT_INPUTS.some((pattern) => {
		const prefix = pattern.replace(/\/\*\*$/, "");
		return normalized === prefix || normalized.startsWith(`${prefix}/`);
	});
}

function extensionCodeHash(extensionPath) {
	return crypto.createHash("sha256").update(fs.readFileSync(path.join(extensionPath, "extension.js"))).digest("hex");
}

function sameWorkspacePath(left, right) {
	const leftPath = path.resolve(left);
	const rightPath = path.resolve(right);
	return process.platform === "win32"
		? leftPath.toLowerCase() === rightPath.toLowerCase()
		: leftPath === rightPath;
}

function collectProblems(root) {
	const diagnostics = [];
	for (const [uri, entries] of vscode.languages.getDiagnostics()) {
		const folder = vscode.workspace.getWorkspaceFolder(uri);
		if (!folder || !sameWorkspacePath(folder.uri.fsPath, root)) continue;
		const relativePath = uri.scheme === "file"
			? path.relative(root, uri.fsPath).split(path.sep).join("/")
			: uri.toString();
		for (const diagnostic of entries) {
			const code = diagnostic.code && typeof diagnostic.code === "object" ? diagnostic.code.value : diagnostic.code;
			diagnostics.push({
				path: relativePath,
				line: diagnostic.range.start.line + 1,
				column: diagnostic.range.start.character + 1,
				severity: ["error", "warning", "information", "hint"][diagnostic.severity] || "unknown",
				source: diagnostic.source || "",
				code: code === undefined || code === null ? "" : String(code),
				message: diagnostic.message,
			});
		}
	}
	diagnostics.sort((left, right) =>
		left.path.localeCompare(right.path) || left.line - right.line || left.column - right.column,
	);
	return diagnostics;
}

function waitForDiagnosticsQuiet(maxWaitMs = 5000, quietMs = 500) {
	return new Promise((resolve) => {
		let quietTimer;
		const finish = () => {
			clearTimeout(quietTimer);
			clearTimeout(maxTimer);
			subscription.dispose();
			resolve();
		};
		const resetQuietTimer = () => {
			clearTimeout(quietTimer);
			quietTimer = setTimeout(finish, quietMs);
		};
		const subscription = vscode.languages.onDidChangeDiagnostics(resetQuietTimer);
		const maxTimer = setTimeout(finish, maxWaitMs);
		resetQuietTimer();
	});
}

async function startProblemsBridge(workspaces) {
	const token = crypto.randomBytes(32).toString("hex");
	const manifests = new Map();
	const server = http.createServer((request, response) => {
		if (request.method !== "POST" || request.url !== "/problems") {
			response.writeHead(404).end();
			return;
		}
		if (request.socket.remoteAddress !== "127.0.0.1" && request.socket.remoteAddress !== "::ffff:127.0.0.1") {
			response.writeHead(403).end();
			return;
		}
		if (request.headers.authorization !== `Bearer ${token}`) {
			response.writeHead(401).end();
			return;
		}
		let body = "";
		request.setEncoding("utf8");
		request.on("data", (chunk) => {
			body += chunk;
			if (body.length > 4096) {
				response.writeHead(413).end();
				request.destroy();
			}
		});
		request.on("end", async () => {
			try {
				const input = JSON.parse(body || "{}");
				const root = typeof input.root === "string" ? input.root : "";
				const folder = (vscode.workspace.workspaceFolders || []).find((candidate) =>
					sameWorkspacePath(candidate.uri.fsPath, root),
				);
				if (!folder || !workspaces.has(folder.uri.toString())) {
					response.writeHead(404).end();
					return;
				}
				if (input.phase === "after") await waitForDiagnosticsQuiet();
				const snapshot = {
					root: folder.uri.fsPath,
					capturedAt: new Date().toISOString(),
					diagnostics: collectProblems(folder.uri.fsPath),
				};
				response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(snapshot));
			} catch (error) {
				response.writeHead(500, { "content-type": "application/json" }).end(JSON.stringify({ error: error.message }));
			}
		});
	});

	await new Promise((resolve, reject) => {
		server.once("error", reject);
		server.listen(0, "127.0.0.1", resolve);
	});
	const address = server.address();
	if (!address || typeof address === "string") {
		server.close();
		throw new Error("Could not resolve the local Problems API address.");
	}
	const publish = (root) => {
		const directory = path.join(root, PROBLEMS_DIRECTORY);
		const endpointPath = path.join(directory, PROBLEMS_ENDPOINT);
		fs.mkdirSync(directory, { recursive: true });
		const temporaryPath = `${endpointPath}.${process.pid}.tmp`;
		fs.writeFileSync(temporaryPath, JSON.stringify({ port: address.port, token }), { mode: 0o600 });
		fs.renameSync(temporaryPath, endpointPath);
		manifests.set(root, endpointPath);
	};
	const unpublish = (root) => {
		const endpointPath = manifests.get(root);
		if (!endpointPath) return;
		try {
			fs.unlinkSync(endpointPath);
		} catch {}
		manifests.delete(root);
	};
	return {
		publish,
		unpublish,
		dispose() {
			for (const root of manifests.keys()) unpublish(root);
			server.close();
		},
	};
}

/** Return true when a workspace folder exposes this repository's Preflight interface. */
function isPreflightWorkspace(folder) {
	const root = folder.uri.fsPath;
	return (
		fs.existsSync(path.join(root, "repo", "ci", "preflight", "init.luau")) &&
		fs.existsSync(path.join(root, "dependencies", "lune", "bootstrap.sh")) &&
		fs.existsSync(path.join(root, "repo", "ci", "entry.luau")) &&
		fs.existsSync(path.join(root, "providers")) &&
		fs.existsSync(path.join(root, "repo", "config", "ci", "preflight"))
	);
}

/** Resolve the repository's MSYS2 Bash without falling back to Windows' WSL launcher. */
function resolveMsysRoot() {
	if (process.env.MSYS2_ROOT) {
		return process.env.MSYS2_ROOT.replaceAll("\\", "/").replace(/\/+$/, "");
	}
	if (process.platform === "win32") {
		const systemDrive = path.win32.parse(process.execPath).root;
		const candidate = path.win32.join(systemDrive, "msys64");
		if (fs.existsSync(path.win32.join(candidate, "usr", "bin", "bash.exe"))) {
			return candidate.replaceAll("\\", "/");
		}
	}
	return undefined;
}

function resolveBash() {
	if (process.env.PREFLIGHT_BASH) {
		return process.env.PREFLIGHT_BASH;
	}
	if (process.platform === "win32") {
		const root = resolveMsysRoot();
		const executable = root ? `${root}/usr/bin/bash.exe` : undefined;
		if (executable && fs.existsSync(executable)) {
			return executable;
		}
		throw new Error("Preflight could not find MSYS2 Bash. Set MSYS2_ROOT or PREFLIGHT_BASH.");
	}
	return "bash";
}

/** Pass workspace paths to MSYS2 in its POSIX form. */
function msysPath(value) {
	const windowsPath = value.match(/^([A-Za-z]):[\\/](.*)$/);
	if (!windowsPath) {
		return value.replaceAll("\\", "/");
	}
	return `/${windowsPath[1].toLowerCase()}/${windowsPath[2].replaceAll("\\", "/")}`;
}

/** Resolve provider binaries and storage from the active VS Code extension profile. */
function providerEnvironment(context) {
	const environment = { ...process.env };
	const msysRoot = process.platform === "win32" ? resolveMsysRoot() : undefined;
	if (msysRoot) {
		const shellBins = [`${msysRoot}/usr/bin`];
		if (fs.existsSync(`${msysRoot}/clangarm64/bin`)) {
			shellBins.unshift(`${msysRoot}/clangarm64/bin`);
			environment.MSYSTEM = environment.MSYSTEM || "CLANGARM64";
		}
		environment.MSYS2_PATH_TYPE = environment.MSYS2_PATH_TYPE || "inherit";
		environment.PATH = [...shellBins, environment.PATH || ""].join(path.delimiter);
	}
	const luauExtension = vscode.extensions.getExtension("JohnnyMorganz.luau-lsp");
	if (luauExtension) {
		const executable = path.join(
			luauExtension.extensionPath,
			"bin",
			process.platform === "win32" ? "server.exe" : "server",
		);
		if (fs.existsSync(executable)) {
			environment.PREFLIGHT_LUAU_LSP = executable;
		}
	}
	const configuredStylua = vscode.workspace.getConfiguration("stylua").get("styluaPath");
	if (typeof configuredStylua === "string" && configuredStylua.length > 0) {
		environment.PREFLIGHT_STYLUA_PATH = configuredStylua;
	}
	environment.PREFLIGHT_VSCODE_GLOBAL_STORAGE = path.dirname(context.globalStorageUri.fsPath);
	return environment;
}

function locateStylua(environment) {
	if (environment.PREFLIGHT_STYLUA_PATH && fs.existsSync(environment.PREFLIGHT_STYLUA_PATH)) {
		return environment.PREFLIGHT_STYLUA_PATH;
	}
	const storageRoot = environment.PREFLIGHT_VSCODE_GLOBAL_STORAGE;
	const extensionRoot = storageRoot ? path.join(storageRoot, "johnnymorganz.stylua") : undefined;
	if (extensionRoot && fs.existsSync(extensionRoot)) {
		const pending = [extensionRoot];
		while (pending.length) {
			const directory = pending.shift();
			for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
				const candidate = path.join(directory, entry.name);
				if (entry.isDirectory()) {
					pending.push(candidate);
				} else if (entry.name.toLowerCase() === (process.platform === "win32" ? "stylua.exe" : "stylua")) {
					return candidate;
				}
			}
		}
	}
	return "stylua";
}

function formatWithStylua(document, root, executable) {
	return new Promise((resolve, reject) => {
		const child = childProcess.spawn(
			executable,
			["--config-path", path.join(root, STYLUA_CONFIG), "--stdin-filepath", document.uri.fsPath, "-"],
			{ cwd: root, windowsHide: true },
		);
		let output = "";
		let errors = "";
		child.stdout.setEncoding("utf8").on("data", (chunk) => (output += chunk));
		child.stderr.setEncoding("utf8").on("data", (chunk) => (errors += chunk));
		child.on("error", reject);
		child.on("close", (code) =>
			code === 0 ? resolve(output) : reject(new Error(errors.trim() || `StyLua exited with status ${code}`)),
		);
		child.stdin.on("error", reject);
		child.stdin.end(document.getText());
	});
}

function registerStyluaActions(context, environment) {
	context.subscriptions.push(
		vscode.languages.registerCodeActionsProvider(
			{ scheme: "file", language: "luau" },
			{
				provideCodeActions(document, _range, actionContext) {
					return actionContext.diagnostics
						.filter((diagnostic) => diagnostic.source === "StyLua")
						.map((diagnostic) => {
							const action = new vscode.CodeAction(
								"Format file with StyLua",
								vscode.CodeActionKind.QuickFix,
							);
							action.diagnostics = [diagnostic];
							action.isPreferred = true;
							action.command = {
								command: STYLUA_FORMAT_COMMAND,
								title: action.title,
								arguments: [document.uri],
							};
							return action;
						});
				},
			},
			{ providedCodeActionKinds: [vscode.CodeActionKind.QuickFix] },
		),
		vscode.commands.registerCommand(STYLUA_FORMAT_COMMAND, async (uri) => {
			const targetUri = uri || vscode.window.activeTextEditor?.document.uri;
			if (!targetUri) return;
			const document = await vscode.workspace.openTextDocument(targetUri);
			const folder = vscode.workspace.getWorkspaceFolder(targetUri);
			if (!folder) return;
			try {
				const original = document.getText();
				const formatted = await formatWithStylua(document, folder.uri.fsPath, locateStylua(environment));
				if (formatted === original) return;
				const edit = new vscode.WorkspaceEdit();
				edit.replace(
					document.uri,
					new vscode.Range(document.positionAt(0), document.positionAt(original.length)),
					formatted,
				);
				await vscode.workspace.applyEdit(edit);
			} catch (error) {
				vscode.window.showErrorMessage(`StyLua formatting failed: ${error instanceof Error ? error.message : error}`);
			}
		}),
	);
}

/** Convert one machine-readable Preflight output line to a VS Code diagnostic. */
function parseDiagnostic(line, root) {
	let record;
	if (typeof line !== "string") {
		record = line;
	} else if (line.startsWith(DIAGNOSTIC_PREFIX)) {
		try {
			record = JSON.parse(line.slice(DIAGNOSTIC_PREFIX.length));
		} catch {
			return undefined;
		}
	} else {
		const match = DIAGNOSTIC_PATTERN.exec(line);
		if (!match) {
			return undefined;
		}
		const [, reportedPath, lineText, columnText, endColumnText, endLineText, severityText, sourceText, message] = match;
		record = {
			path: reportedPath,
			line: Number(lineText),
			column: Number(columnText),
			endColumn: Number(endColumnText),
			endLine: endLineText ? Number(endLineText) : undefined,
			severity: severityText,
			source: sourceText,
			message,
		};
	}

	if (!record || typeof record.path !== "string" || typeof record.message !== "string") {
		return undefined;
	}
	const lineNumber = Number(record.line);
	const column = Number(record.column);
	const endColumn = Number(record.endColumn);
	const endLine = record.endLine === undefined ? undefined : Number(record.endLine);
	if (![lineNumber, column, endColumn].every(Number.isInteger) || lineNumber < 1 || column < 1) {
		return undefined;
	}

	const filePath = path.isAbsolute(record.path) ? record.path : path.join(root, record.path);
	const severity = {
		error: vscode.DiagnosticSeverity.Error,
		warning: vscode.DiagnosticSeverity.Warning,
		info: vscode.DiagnosticSeverity.Information,
	}[record.severity];
	if (severity === undefined) {
		return undefined;
	}
	const start = new vscode.Position(lineNumber - 1, column - 1);
	const finish = endLine !== undefined
		? new vscode.Position(Math.max(lineNumber - 1, endLine - 1), Math.max(0, endColumn - 1))
		: new vscode.Position(lineNumber - 1, Math.max(column, endColumn) - 1);
	const diagnostic = new vscode.Diagnostic(new vscode.Range(start, finish), record.message, severity);
	diagnostic.relatedInformation = (record.relatedInformation || []).map((related) => {
		const relatedPath = path.isAbsolute(related.path) ? related.path : path.join(root, related.path);
		const relatedUri = vscode.Uri.file(relatedPath);
		const relatedPosition = new vscode.Position(related.line - 1, related.column - 1);
		const relatedLocation = new vscode.Location(
			relatedUri,
			new vscode.Range(relatedPosition, relatedPosition.translate(0, 1)),
		);
		return new vscode.DiagnosticRelatedInformation(relatedLocation, related.message);
	});
	diagnostic.source = {
		preflight: "Preflight",
		luauLsp: "Luau LSP",
		stylua: "StyLua",
		luaurc: "luaurc",
		lune: "Lune",
	}[record.source] || record.source;
	return { uri: vscode.Uri.file(filePath), diagnostic };
}

/** Create a diagnostic on the Preflight entry when the runner fails without a structured finding. */
function runnerDiagnostic(root, message) {
	const uri = vscode.Uri.file(path.join(root, "repo", "ci", "preflight", "init.luau"));
	const diagnostic = new vscode.Diagnostic(
		new vscode.Range(new vscode.Position(0, 0), new vscode.Position(0, 1)),
		message,
		vscode.DiagnosticSeverity.Error,
	);
	diagnostic.source = OWNER;
	return { uri, diagnostic };
}

/** Replace this workspace's Problems with the latest Preflight diagnostic table. */
function publishDiagnostics(records, root, collection, state) {
	const grouped = new Map();
	for (const record of records) {
		const parsed = parseDiagnostic(record, root);
		if (!parsed) {
			continue;
		}
		const key = parsed.uri.toString();
		const diagnostics = grouped.get(key) || { uri: parsed.uri, entries: [] };
		diagnostics.entries.push(parsed.diagnostic);
		grouped.set(key, diagnostics);
	}

	for (const previous of state.uris) {
		if (!grouped.has(previous)) {
			collection.delete(vscode.Uri.parse(previous));
		}
	}
	for (const { uri, entries } of grouped.values()) {
		collection.set(uri, entries);
	}
	state.uris = new Set(grouped.keys());
	const diagnostics = [...grouped.values()].flatMap(({ entries }) => entries);
	const errors = diagnostics.filter((diagnostic) => diagnostic.severity === vscode.DiagnosticSeverity.Error).length;
	const warnings = diagnostics.filter((diagnostic) => diagnostic.severity === vscode.DiagnosticSeverity.Warning).length;
	const information = diagnostics.filter((diagnostic) => diagnostic.severity === vscode.DiagnosticSeverity.Information).length;
	state.outcome = { errors, warnings, information, failed: false };
}

/** Apply one streamed runner record, replacing the panel as the diagnostic table changes. */
function processOutputLine(line, root, collection, state) {
	if (line === "::preflight-start::") {
		for (const uri of state.uris) collection.delete(vscode.Uri.parse(uri));
		state.uris = new Set();
		state.legacyDiagnostics = [];
		state.receivedSnapshot = false;
		state.outcome = undefined;
		return;
	}
	if (line.startsWith(DIAGNOSTICS_SNAPSHOT_PREFIX)) {
		try {
			const decoded = JSON.parse(line.slice(DIAGNOSTICS_SNAPSHOT_PREFIX.length));
			state.receivedSnapshot = true;
			publishDiagnostics(Array.isArray(decoded) ? decoded : [], root, collection, state);
		} catch (error) {
			state.streamError = `Preflight emitted an invalid diagnostics snapshot: ${error.message}`;
		}
		return;
	}
	const parsed = parseDiagnostic(line, root);
	if (parsed) {
		state.receivedSnapshot = true;
		state.legacyDiagnostics.push({
			path: path.relative(root, parsed.uri.fsPath).split(path.sep).join("/"),
			line: parsed.diagnostic.range.start.line + 1,
			column: parsed.diagnostic.range.start.character + 1,
			endColumn: parsed.diagnostic.range.end.character + 1,
			endLine: parsed.diagnostic.range.end.line + 1,
			severity: ["error", "warning", "info"][parsed.diagnostic.severity],
			source: parsed.diagnostic.source,
			message: parsed.diagnostic.message,
		});
		publishDiagnostics(state.legacyDiagnostics, root, collection, state);
	}
}

/** Show the aggregate state of every attached workspace in VS Code's status bar. */
function updateStatus(status, workspaces) {
	const states = [...workspaces.values()];
	if (status.reloadPending) {
		status.text = "$(warning) Preflight: Reload required";
		status.tooltip = "Preflight was updated. Click to reload this VS Code window and activate the update.";
		status.command = "preflight.promptReload";
		status.show();
		return;
	}
	status.command = "preflight.analyze";
	if (states.length === 0) {
		status.hide();
		return;
	}
	if (states.some((state) => state.process)) {
		status.text = "$(sync~spin) Preflight: Checking";
		status.tooltip = "Preflight is analyzing workspace files and configured providers.";
		status.backgroundColor = undefined;
		status.show();
		return;
	}
	if (states.some((state) => state.timer || state.pending)) {
		status.text = "$(clock) Preflight: Queued";
		status.tooltip = "Preflight will rerun after the current workspace changes settle.";
		status.backgroundColor = undefined;
		status.show();
		return;
	}
	const outcomes = states.map((state) => state.outcome).filter(Boolean);
	if (outcomes.length !== states.length) {
		status.text = "$(sync~spin) Preflight: Starting";
		status.tooltip = "Preflight is starting for this workspace.";
		status.show();
		return;
	}
	const errors = outcomes.reduce((total, outcome) => total + outcome.errors, 0);
	const warnings = outcomes.reduce((total, outcome) => total + outcome.warnings, 0);
	const information = outcomes.reduce((total, outcome) => total + outcome.information, 0);
	const failed = outcomes.some((outcome) => outcome.failed);
	if (failed || errors > 0) {
		status.text = `$(error) Preflight: ${errors || "Run failed"}`;
		status.tooltip = `${errors} error(s), ${warnings} warning(s), ${information} information finding(s). Click to run Preflight again.`;
	} else if (warnings > 0) {
		status.text = `$(warning) Preflight: ${warnings} warning${warnings === 1 ? "" : "s"}`;
		status.tooltip = `${warnings} warning(s), ${information} information finding(s). Click to run Preflight again.`;
	} else if (information > 0) {
		status.text = `$(info) Preflight: Ready (${information})`;
		status.tooltip = `${information} information finding(s). Click to run Preflight again.`;
	} else {
		status.text = "$(check) Preflight: Ready";
		status.tooltip = "No Preflight findings. Click to run Preflight again.";
	}
	status.show();
}

/** Run one Preflight process for a root and schedule one follow-up if files changed during it. */
function analyze(root, collection, state, status, workspaces) {
	if (state.disposed) {
		return;
	}
	if (state.process) {
		state.pending = true;
		return;
	}
	state.outcome = undefined;
	updateStatus(status, workspaces);

	const environment = { ...state.providerEnvironment, CI_EVENT: "workflow_dispatch" };
	if (environment.USERPROFILE) {
		environment.HOME = environment.USERPROFILE;
	}
	const watcher = msysPath(path.join(root, "repo", "ci", "preflight", "watch", "watch.sh"));
	const child = childProcess.spawn(resolveBash(), [watcher, "--once"], {
		cwd: root,
		env: environment,
		windowsHide: true,
	});
	state.process = child;
	state.receivedSnapshot = false;
	state.legacyDiagnostics = [];
	state.streamError = undefined;
	updateStatus(status, workspaces);
	let output = "";
	let pendingLine = "";
	const consumeChunk = (chunk) => {
		output += chunk;
		const lines = `${pendingLine}${chunk}`.split(/\r?\n/);
		pendingLine = lines.pop() || "";
		for (const line of lines) processOutputLine(line, root, collection, state);
	};
	child.stdout.setEncoding("utf8").on("data", consumeChunk);
	child.stderr.setEncoding("utf8").on("data", consumeChunk);
	child.on("error", (error) => {
		output += `${error.message}\n`;
		pendingLine += `${error.message}\n`;
	});
	child.on("close", (exitCode) => {
		if (pendingLine) processOutputLine(pendingLine, root, collection, state);
		state.process = undefined;
		if (state.disposed) {
			return;
		}
		if (!state.receivedSnapshot && (exitCode ?? 1) !== 0) {
			const detail = output.split(/\r?\n/).find((line) => line.trim() !== "") || `Preflight exited with status ${exitCode}`;
			const fallback = runnerDiagnostic(root, state.streamError || `Preflight could not complete: ${detail}`);
			collection.set(fallback.uri, [fallback.diagnostic]);
			state.uris.add(fallback.uri.toString());
			state.outcome = { errors: 1, warnings: 0, information: 0, failed: true };
		} else if (state.outcome) {
			state.outcome.failed = (exitCode ?? 1) !== 0;
		}
		updateStatus(status, workspaces);
		if (state.pending && !state.disposed) {
			state.pending = false;
			analyze(root, collection, state, status, workspaces);
		}
	});
}

/** Debounce filesystem and document-save notifications before invoking Preflight. */
function schedule(root, collection, state, status, workspaces) {
	if (state.disposed) {
		return;
	}
	if (state.timer) {
		clearTimeout(state.timer);
	}
	state.outcome = undefined;
	updateStatus(status, workspaces);
	state.timer = setTimeout(() => {
		state.timer = undefined;
		analyze(root, collection, state, status, workspaces);
	}, DEBOUNCE_MS);
}

/** Stop one workspace's timers, file watches, and active child process. */
function disposeState(state) {
	if (state.disposed) {
		return;
	}
	state.disposed = true;
	if (state.timer) {
		clearTimeout(state.timer);
	}
	if (state.reloadTimer) {
		clearInterval(state.reloadTimer);
	}
	if (state.process) {
		state.process.kill();
	}
	for (const disposable of state.disposables) {
		disposable.dispose();
	}
}

/** Activate Preflight diagnostics only for workspace folders with the expected interface. */
async function activate(context) {
	const collection = vscode.languages.createDiagnosticCollection(OWNER);
	const workspaces = new Map();
	let problemsBridge;
	try {
		problemsBridge = await startProblemsBridge(workspaces);
	} catch (error) {
		console.error(`Could not start the local VS Code Problems API: ${error.message}`);
		problemsBridge = { publish() {}, unpublish() {}, dispose() {} };
	}
	const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
	status.reloadPending = false;
	status.command = "preflight.analyze";
	status.text = "$(sync~spin) Preflight: Starting";
	status.tooltip = "Preflight is loading its configured providers.";
	status.show();
	context.subscriptions.push(status);
	const activations = PROVIDER_EXTENSIONS.map(async (identifier) => {
		const extension = vscode.extensions.getExtension(identifier);
		if (extension && !extension.isActive) {
			await extension.activate();
		}
	});
	await Promise.allSettled(activations);
	const environment = providerEnvironment(context);
	registerStyluaActions(context, environment);
	const loadedCodeHash = extensionCodeHash(context.extensionPath);
	const promptedReloadHashes = new Set();

	async function promptForReload() {
		const choice = await vscode.window.showInformationMessage(
			"Preflight was updated. Reload this VS Code window to activate the update.",
			"Reload Window",
			"Later",
		);
		if (choice === "Reload Window") {
			await vscode.commands.executeCommand("workbench.action.reloadWindow");
		}
	}

	async function checkReloadMarker(root) {
		const marker = path.join(root, "build", "run", "preflight-extension", "artifacts", "preflight-reload-required.sha256");
		if (!fs.existsSync(marker)) {
			return;
		}
		let requestedHash;
		try {
			requestedHash = fs.readFileSync(marker, "utf8").trim();
		} catch {
			return;
		}
		if (!requestedHash) return;
		if (requestedHash === loadedCodeHash) {
			try { fs.unlinkSync(marker); } catch {}
			status.reloadPending = false;
			updateStatus(status, workspaces);
			return;
		}
		status.reloadPending = true;
		updateStatus(status, workspaces);
		const promptKey = `preflight.reloadPrompted.${requestedHash}`;
		if (promptedReloadHashes.has(requestedHash) || context.globalState.get(promptKey)) return;
		promptedReloadHashes.add(requestedHash);
		await context.globalState.update(promptKey, true);
		await promptForReload();
	}

	context.subscriptions.push(vscode.commands.registerCommand("preflight.promptReload", async () => {
		const root = [...workspaces.keys()][0];
		if (!root) return;
		const marker = path.join(vscode.Uri.parse(root).fsPath, "build", "run", "preflight-extension", "artifacts", "preflight-reload-required.sha256");
		if (!fs.existsSync(marker)) return;
		await promptForReload();
	}));

	function attach(folder) {
		if (!isPreflightWorkspace(folder) || workspaces.has(folder.uri.toString())) {
			return;
		}

		const root = folder.uri.fsPath;
		const state = {
			process: undefined,
			providerEnvironment: environment,
			pending: false,
			timer: undefined,
			uris: new Set(),
			outcome: undefined,
			disposed: false,
			disposables: [],
			reloadTimer: undefined,
		};
		workspaces.set(folder.uri.toString(), state);
		problemsBridge.publish(root);

		const watchers = PREFLIGHT_INPUTS.map((pattern) =>
			vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(folder, pattern)),
		);
		const changed = (uri) => {
			const relative = path.relative(root, uri.fsPath).split(path.sep).join("/");
			if (!isPreflightInput(relative)) {
				return;
			}
			schedule(root, collection, state, status, workspaces);
		};
		for (const watcher of watchers) {
			state.disposables.push(
				watcher,
				watcher.onDidChange(changed),
				watcher.onDidCreate(changed),
				watcher.onDidDelete(changed),
			);
		}
		context.subscriptions.push({ dispose: () => disposeState(state) });
		state.reloadTimer = setInterval(() => void checkReloadMarker(root), 1000);
		void checkReloadMarker(root);
		updateStatus(status, workspaces);
		analyze(root, collection, state, status, workspaces);
	}

	function detach(folder) {
		const key = folder.uri.toString();
		const state = workspaces.get(key);
		if (!state) {
			return;
		}
		disposeState(state);
		problemsBridge.unpublish(folder.uri.fsPath);
		for (const uri of state.uris) {
			collection.delete(vscode.Uri.parse(uri));
		}
		workspaces.delete(key);
		updateStatus(status, workspaces);
	}

	for (const folder of vscode.workspace.workspaceFolders || []) {
		attach(folder);
	}
	context.subscriptions.push(
		{ dispose: () => problemsBridge.dispose() },
		collection,
		vscode.workspace.onDidChangeWorkspaceFolders((event) => {
			for (const folder of event.removed) {
				detach(folder);
			}
			for (const folder of event.added) {
				attach(folder);
			}
		}),
		vscode.workspace.onDidSaveTextDocument((document) => {
			const folder = vscode.workspace.getWorkspaceFolder(document.uri);
			if (folder) {
				const relative = path.relative(folder.uri.fsPath, document.uri.fsPath);
				if (!isPreflightInput(relative)) return;
				const state = workspaces.get(folder.uri.toString());
				if (state) {
					schedule(folder.uri.fsPath, collection, state, status, workspaces);
				}
			}
		}),
		vscode.commands.registerCommand("preflight.analyze", () => {
			for (const folder of vscode.workspace.workspaceFolders || []) {
				const state = workspaces.get(folder.uri.toString());
				if (state) {
					schedule(folder.uri.fsPath, collection, state, status, workspaces);
				}
			}
		}),
	);
}

/** Stop pending processes when VS Code unloads the extension host. */
function deactivate() {}

module.exports = { activate, deactivate };
