"use strict";

const crypto = require("node:crypto");
const path = require("node:path");

const WATCH_GLOBS = ["dependencies/**", ".vscode/config/**", ".vscode/settings.json", ".github/**", "source/**", "rules/**", ".luaurc", "tsconfig.json"];
const SETUP_FILES = new Set([
	"dependencies/dependencies.toml",
	"dependencies/dependencies.lock",
	".vscode/config/luau/.luaurc",
	".vscode/config/typescript/tsconfig.json",
]);

function activate({ vscode, workspaceFolder, subscriptions, signal, asAbsolutePath }) {
	const root = workspaceFolder.uri?.fsPath || workspaceFolder.fsPath;
	const identity = process.platform === "win32" ? path.resolve(root).toLowerCase() : path.resolve(root);
	const workspaceId = crypto.createHash("sha1").update(identity).digest("hex").slice(0, 10);
	const command = suffix => `editorIntegration.${workspaceId}.${suffix}`;
	const output = vscode.window.createOutputChannel(`Workspace Setup: ${path.basename(root)}`);
	const setupStatus = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 21);
	const checkStatus = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 20);
	const diagnostics = vscode.languages.createDiagnosticCollection(`workspace-preflight-${workspaceId}`);
	const owned = [output, setupStatus, checkStatus, diagnostics];
	let setupFailed = false;
	let setupReady = false;
	let checkGeneration = 0;
	let disposed = false;
	let callback;
	let watchTimer;
	let pendingAction = "check";

	setupStatus.command = command("runSetup");
	setupStatus.text = "$(sync~spin) Loading dependencies";
	setupStatus.tooltip = "Preparing workspace dependencies. Click to retry setup.";
	setupStatus.show();
	checkStatus.command = command("check");
	checkStatus.text = "$(sync~spin) Waiting for checks";
	checkStatus.tooltip = "Workspace preflight status";
	checkStatus.show();

	function showError(message, detail) {
		setupFailed = true;
		setupStatus.text = "$(error) Dependency setup failed";
		setupStatus.tooltip = detail || message;
		output.appendLine(`[error] ${message}`);
		if (detail) output.appendLine(detail);
		output.show(true);
	}

	function updateDependencies(event = {}) {
		if (disposed) return;
		if (event.error || (event.exitCode !== undefined && event.exitCode !== 0)) {
			showError(event.message || "Dependency setup failed", event.error || `Process exited with code ${event.exitCode}`);
			setupReady = false;
			return;
		}
		if (event.message) {
			const progress = Number.isFinite(event.completed) && Number.isFinite(event.total) ? ` ${event.completed}/${event.total}` : "";
			setupStatus.text = event.complete ? "$(check) Dependencies ready" : `$(sync~spin) ${event.message}${progress}`;
			setupStatus.tooltip = event.detail || event.message;
			output.appendLine(`${event.complete ? "[ready]" : "[setup]"} ${event.message}${event.detail ? `: ${event.detail}` : ""}`);
		}
		if (event.complete) {
			setupReady = true;
			setupFailed = false;
			setupStatus.text = "$(check) Dependencies ready";
			setupStatus.tooltip = "Dependencies are available. Click to run setup again.";
		}
	}

	function publishPreflight(result = {}) {
		if (disposed) return;
		const generation = Number(result.generation);
		if (Number.isFinite(generation) && generation < checkGeneration) return;
		if (Number.isFinite(generation)) checkGeneration = generation;
	const dirty = new Set(vscode.workspace.textDocuments.filter(document => document.isDirty && isInWorkspace(document.uri)).map(document => document.uri.toString()));
		const byFile = new Map();
		const items = Array.isArray(result.findings) ? result.findings : [];
		for (const finding of items) {
			if (!finding || typeof finding.file !== "string") continue;
			const uri = path.isAbsolute(finding.file) ? vscode.Uri.file(finding.file) : vscode.Uri.file(asAbsolutePath(finding.file));
			if (dirty.has(uri.toString())) continue;
			const startLine = Math.max(0, Number(finding.line || 1) - 1);
			const startColumn = Math.max(0, Number(finding.column || 1) - 1);
			const diagnostic = new vscode.Diagnostic(
				new vscode.Range(startLine, startColumn, startLine, startColumn + 1),
				`${finding.source ? `[${finding.source}] ` : ""}${finding.message || "Check failed"}`,
				finding.severity === "warning" ? vscode.DiagnosticSeverity.Warning : finding.severity === "information" ? vscode.DiagnosticSeverity.Information : vscode.DiagnosticSeverity.Error,
			);
			diagnostic.source = finding.source || "Preflight";
			const key = uri.toString();
			if (!byFile.has(key)) byFile.set(key, { uri, diagnostics: [] });
			byFile.get(key).diagnostics.push(diagnostic);
		}
		diagnostics.clear();
		for (const { uri, diagnostics: fileDiagnostics } of byFile.values()) diagnostics.set(uri, fileDiagnostics);
		if (result.error) {
			checkStatus.text = "$(error) Workspace checks failed";
			checkStatus.tooltip = result.error;
			output.appendLine(`[check error] ${result.error}`);
			output.show(true);
		} else if (items.some(item => item.severity === "error")) {
			checkStatus.text = "$(error) Workspace checks failed";
			checkStatus.tooltip = `${items.filter(item => item.severity === "error").length} error(s); click to rerun checks`;
		} else if (items.length) {
			checkStatus.text = "$(warning) Workspace checks";
			checkStatus.tooltip = `${items.length} warning(s); click to rerun checks`;
		} else if (setupReady) {
			checkStatus.text = "$(check) Workspace checks passed";
			checkStatus.tooltip = "Preflight checks passed. Click to rerun.";
		}
	}

	function log(message) { if (!disposed && message) output.appendLine(String(message)); }
	function isInWorkspace(uri) {
		const relative = path.relative(root, uri.fsPath);
		return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
	}
	function dispatch(action) {
		if (!callback) return;
		Promise.resolve().then(() => callback(action)).catch(error => log(`[bridge callback error] ${error instanceof Error ? error.message : String(error)}`));
	}
	function schedule(action) {
		if (!callback || disposed) return;
		if (action === "run") pendingAction = "run";
		if (watchTimer) clearTimeout(watchTimer);
		watchTimer = setTimeout(() => {
			watchTimer = undefined;
			const nextAction = pendingAction;
			pendingAction = "check";
			if (!disposed) dispatch(nextAction);
		}, 350);
	}
	function startWatching(controllerCallback) {
		callback = controllerCallback;
		for (const glob of WATCH_GLOBS) {
			const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(workspaceFolder, glob));
			const watchEvent = uri => {
				const relative = path.relative(root, uri.fsPath).split(path.sep).join("/");
				schedule(SETUP_FILES.has(relative) ? "run" : "check");
			};
			owned.push(watcher, watcher.onDidCreate(watchEvent), watcher.onDidChange(watchEvent), watcher.onDidDelete(watchEvent));
		}
		owned.push(vscode.workspace.onDidSaveTextDocument(document => {
			if (isInWorkspace(document.uri)) schedule(SETUP_FILES.has(path.relative(root, document.uri.fsPath).split(path.sep).join("/")) ? "run" : "check");
		}));
		owned.push(vscode.workspace.onDidOpenTextDocument(document => { if (isInWorkspace(document.uri)) scheduleCheck(); }));
		owned.push(vscode.workspace.onDidChangeTextDocument(event => {
			if (!isInWorkspace(event.document.uri)) return;
			diagnostics.delete(event.document.uri);
			scheduleCheck();
		}));
		owned.push(vscode.commands.registerCommand(command("showOutput"), () => output.show(true)));
		owned.push(vscode.commands.registerCommand(command("runSetup"), () => dispatch("run")));
		owned.push(vscode.commands.registerCommand(command("check"), () => dispatch("check")));
		return { dispose() { callback = undefined; } };
	}
	function scheduleCheck() { schedule("check"); }

	const api = {
		start: startWatching,
		run() { return dispatch("run"); },
		check() { return dispatch("check"); },
		updateDependencies,
		publishPreflight,
		startWatching,
		showOutput() { output.show(true); },
		beginCheck(generation) {
			if (disposed || generation < checkGeneration) return false;
			checkGeneration = generation;
			checkStatus.text = "$(sync~spin) Checking workspace";
			checkStatus.tooltip = "Running TypeScript and Luau checks";
			return true;
		},
		beginSetup(generation) {
			if (disposed || generation < checkGeneration) return false;
			checkGeneration = generation;
			diagnostics.clear();
			checkStatus.text = "$(sync~spin) Loading dependencies";
			checkStatus.tooltip = "Waiting for dependency setup before checking";
			return true;
		},
		log,
		dispose() {
			if (disposed) return;
			disposed = true;
			if (watchTimer) clearTimeout(watchTimer);
			for (const item of owned.reverse()) { try { item.dispose(); } catch { /* best-effort shutdown */ } }
		},
	};
	subscriptions.push(api);
	if (signal) signal.addEventListener("abort", api.dispose, { once: true });
	return api;
}

module.exports = { activate };
