"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const vscode = require("vscode");

const OWNER = "preflight";
const DEBOUNCE_MS = 500;
const PROVIDER_EXTENSIONS = ["JohnnyMorganz.luau-lsp", "JohnnyMorganz.stylua"];
const DIAGNOSTIC_PATTERN = /^(.*):(\d+):(\d+):(\d+): (error|warning|info): (.*)$/;

/** Return true when a workspace folder exposes this repository's Preflight interface. */
function isPreflightWorkspace(folder) {
	const root = folder.uri.fsPath;
	return (
		fs.existsSync(path.join(root, "ci", "preflight", "init.luau")) &&
		fs.existsSync(path.join(root, "ci", "toolchain", "lune.sh")) &&
		fs.existsSync(path.join(root, "ci", "entry.luau")) &&
		fs.existsSync(path.join(root, "config", "preflight"))
	);
}

/** Prefer MSYS2 Bash on Windows while allowing normal Bash installations elsewhere. */
function resolveBash() {
	if (process.platform === "win32") {
		const candidates = [
			process.env.PREFLIGHT_BASH,
			process.env.MSYS2_ROOT ? path.join(process.env.MSYS2_ROOT, "usr", "bin", "bash.exe") : undefined,
			"C:\\msys64\\usr\\bin\\bash.exe",
		];
		for (const candidate of candidates) {
			if (candidate && fs.existsSync(candidate)) {
				return candidate;
			}
		}
	}
	return "bash";
}

/** Resolve provider binaries and storage from the active VS Code extension profile. */
function providerEnvironment(context) {
	const environment = { ...process.env };
	if (process.platform === "win32") {
		const msysRoot = environment.MSYS2_ROOT || "C:\\msys64";
		const shellBins = [path.join(msysRoot, "usr", "bin")];
		if (fs.existsSync(path.join(msysRoot, "clangarm64", "bin"))) {
			shellBins.unshift(path.join(msysRoot, "clangarm64", "bin"));
			environment.MSYSTEM = environment.MSYSTEM || "CLANGARM64";
		}
		environment.MSYS2_ROOT = msysRoot;
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

/** Convert one machine-readable Preflight output line to a VS Code diagnostic. */
function parseDiagnostic(line, root) {
	const match = DIAGNOSTIC_PATTERN.exec(line);
	if (!match) {
		return undefined;
	}

	const [, reportedPath, lineText, columnText, endColumnText, severityText, message] = match;
	const lineNumber = Number(lineText);
	const column = Number(columnText);
	const endColumn = Number(endColumnText);
	if (![lineNumber, column, endColumn].every(Number.isInteger) || lineNumber < 1 || column < 1) {
		return undefined;
	}

	const filePath = path.isAbsolute(reportedPath) ? reportedPath : path.join(root, reportedPath);
	const severity = {
		error: vscode.DiagnosticSeverity.Error,
		warning: vscode.DiagnosticSeverity.Warning,
		info: vscode.DiagnosticSeverity.Information,
	}[severityText];
	const start = new vscode.Position(lineNumber - 1, column - 1);
	const finish = new vscode.Position(lineNumber - 1, Math.max(column, endColumn) - 1);
	const diagnostic = new vscode.Diagnostic(new vscode.Range(start, finish), message, severity);
	diagnostic.source = OWNER;
	return { uri: vscode.Uri.file(filePath), diagnostic };
}

/** Create a diagnostic on the Preflight entry when the runner fails without a structured finding. */
function runnerDiagnostic(root, message) {
	const uri = vscode.Uri.file(path.join(root, "ci", "preflight", "init.luau"));
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
}

/** Run one Preflight process for a root and schedule one follow-up if files changed during it. */
function analyze(root, collection, state) {
	if (state.disposed) {
		return;
	}
	if (state.process) {
		state.pending = true;
		return;
	}

	const environment = { ...state.providerEnvironment, CI_EVENT: "workflow_dispatch" };
	if (environment.USERPROFILE) {
		environment.HOME = environment.USERPROFILE;
	}
	const child = childProcess.spawn(resolveBash(), ["ci/preflight/watch.sh", "--once"], {
		cwd: root,
		env: environment,
		windowsHide: true,
	});
	state.process = child;
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
		if (state.pending && !state.disposed) {
			state.pending = false;
			analyze(root, collection, state);
		}
	});
}

/** Debounce filesystem and document-save notifications before invoking Preflight. */
function schedule(root, collection, state) {
	if (state.disposed) {
		return;
	}
	if (state.timer) {
		clearTimeout(state.timer);
	}
	state.timer = setTimeout(() => {
		state.timer = undefined;
		analyze(root, collection, state);
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
	const activations = PROVIDER_EXTENSIONS.map(async (identifier) => {
		const extension = vscode.extensions.getExtension(identifier);
		if (extension && !extension.isActive) {
			await extension.activate();
		}
	});
	await Promise.allSettled(activations);
	const environment = providerEnvironment(context);

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
			disposed: false,
			disposables: [],
		};
		workspaces.set(folder.uri.toString(), state);

		const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(folder, "**/*"));
		const changed = (uri) => {
			const relative = path.relative(root, uri.fsPath).split(path.sep).join("/");
			if (/(^|\/)(\.git|build|node_modules)(\/|$)/.test(relative)) {
				return;
			}
			schedule(root, collection, state);
		};
		state.disposables.push(watcher, watcher.onDidChange(changed), watcher.onDidCreate(changed), watcher.onDidDelete(changed));
		context.subscriptions.push({ dispose: () => disposeState(state) });
		analyze(root, collection, state);
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
				const state = workspaces.get(folder.uri.toString());
				if (state) {
					schedule(folder.uri.fsPath, collection, state);
				}
			}
		}),
		vscode.commands.registerCommand("preflight.analyze", () => {
			for (const folder of vscode.workspace.workspaceFolders || []) {
				const state = workspaces.get(folder.uri.toString());
				if (state) {
					schedule(folder.uri.fsPath, collection, state);
				}
			}
		}),
	);
}

/** Stop pending processes when VS Code unloads the extension host. */
function deactivate() {}

module.exports = { activate, deactivate };
