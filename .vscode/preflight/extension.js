"use strict";

const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const vscode = require("vscode");

const OWNER = "preflight";
const DEBOUNCE_MS = 500;
const PROVIDER_EXTENSIONS = ["JohnnyMorganz.luau-lsp", "JohnnyMorganz.stylua"];
const STYLUA_FORMAT_COMMAND = "preflight.styluaFormatDocument";
const STYLUA_CONFIG = "repo/config/luau/stylua/.stylua.toml";
const DIAGNOSTIC_PATTERN = /^(.*):(\d+):(\d+):(\d+)(?::(\d+))?: (error|warning|info): ([^:]+): (.*)$/;
const DIAGNOSTIC_PREFIX = "::diagnostic::";
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

/** Prefer MSYS2 Bash on Windows while allowing normal Bash installations elsewhere. */
function resolveBash() {
	if (process.env.PREFLIGHT_BASH) {
		return process.env.PREFLIGHT_BASH;
	}
	if (process.platform === "win32" && process.env.MSYS2_ROOT) {
		const executable = path.join(process.env.MSYS2_ROOT, "usr", "bin", "bash.exe");
		if (fs.existsSync(executable)) {
			return executable;
		}
	}
	return "bash";
}

/** Resolve provider binaries and storage from the active VS Code extension profile. */
function providerEnvironment(context) {
	const environment = { ...process.env };
	if (process.platform === "win32" && environment.MSYS2_ROOT) {
		const msysRoot = environment.MSYS2_ROOT;
		const shellBins = [path.join(msysRoot, "usr", "bin")];
		if (fs.existsSync(path.join(msysRoot, "clangarm64", "bin"))) {
			shellBins.unshift(path.join(msysRoot, "clangarm64", "bin"));
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
	if (process.platform === "win32") {
		// WSL translates these native paths before the POSIX preflight process starts.
		const mappings = (environment.WSLENV || "").split(":").filter(Boolean);
		for (const name of ["PREFLIGHT_LUAU_LSP", "PREFLIGHT_STYLUA_PATH", "PREFLIGHT_VSCODE_GLOBAL_STORAGE"]) {
			if (!environment[name]) {
				continue;
			}
			const index = mappings.findIndex((entry) => entry.split("/")[0] === name);
			if (index < 0) {
				mappings.push(`${name}/p`);
			} else {
				const [, flags = ""] = mappings[index].split("/");
				mappings[index] = `${name}/${flags.includes("p") ? flags : `${flags}p`}`;
			}
		}
		environment.WSLENV = mappings.join(":");
	}
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
	if (line.startsWith(DIAGNOSTIC_PREFIX)) {
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

/** Parse structured findings and replace only the diagnostics owned by this workspace run. */
function publishOutput(output, exitCode, root, collection, state) {
	const grouped = new Map();
	for (const line of output.split(/\r?\n/)) {
		const parsed = parseDiagnostic(line, root);
		if (!parsed) {
			continue;
		}
		const key = parsed.uri.toString();
		const diagnostics = grouped.get(key) || { uri: parsed.uri, entries: [] };
		diagnostics.entries.push(parsed.diagnostic);
		grouped.set(key, diagnostics);
	}

	if (exitCode !== 0 && grouped.size === 0) {
		const detail = output.split(/\r?\n/).find((line) => line.trim() !== "") || `Preflight exited with status ${exitCode}`;
		const fallback = runnerDiagnostic(root, `Preflight could not complete: ${detail}`);
		grouped.set(fallback.uri.toString(), { uri: fallback.uri, entries: [fallback.diagnostic] });
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
	state.outcome = { errors, warnings, information, failed: exitCode !== 0 };
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
	const child = childProcess.spawn(resolveBash(), ["repo/ci/preflight/watch/watch.sh", "--once"], {
		cwd: root,
		env: environment,
		windowsHide: true,
	});
	state.process = child;
	updateStatus(status, workspaces);
	let output = "";
	child.stdout.setEncoding("utf8").on("data", (chunk) => {
		output += chunk;
	});
	child.stderr.setEncoding("utf8").on("data", (chunk) => {
		output += chunk;
	});
	child.on("error", (error) => {
		output += `${error.message}\n`;
	});
	child.on("close", (exitCode) => {
		state.process = undefined;
		if (state.disposed) {
			return;
		}
		publishOutput(output, exitCode ?? 1, root, collection, state);
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
