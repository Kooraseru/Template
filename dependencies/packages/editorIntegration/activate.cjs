"use strict";

const fs = require("node:fs");
const crypto = require("node:crypto");
const path = require("node:path");

const { registerRuleActions } = require("./ruleActions.cjs");
const { registerRuleSettings } = require("./ruleSettings.cjs");
function activate({ vscode, workspaceFolder, subscriptions, signal, asAbsolutePath }, workflow = JSON.parse(fs.readFileSync(path.join(__dirname, "../../../.vscode/config/workflow.json"), "utf8"))) {
	const setupLabels = workflow.dependencies.status;
	const setupFiles = new Set(workflow.watch.setupInputs);
	const root = workspaceFolder.uri?.fsPath || workspaceFolder.fsPath;
	const identity = process.platform === "win32" ? path.resolve(root).toLowerCase() : path.resolve(root);
	const workspaceId = crypto.createHash("sha1").update(identity).digest("hex").slice(0, 10);
	const command = suffix => `editorIntegration.${workspaceId}.${suffix}`;
	const output = vscode.window.createOutputChannel(`Workspace Setup: ${path.basename(root)}`);
	const setupStatus = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 21);
	const checkStatus = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 20);
	const diagnostics = vscode.languages.createDiagnosticCollection(`workspace-preflight-${workspaceId}`);
	const rulesDiagnostics = vscode.languages.createDiagnosticCollection(`workspace-rules-${workspaceId}`);
	const checks = {
		compile: { status: checkStatus, diagnostics, config: workflow.checks, generation: 0 },
		rules: { diagnostics: rulesDiagnostics, config: workflow.rules, generation: 0 },
	};
	const actionSources = new Map();
	const compileFindings = new Map();
	const owned = [output, setupStatus, checkStatus, diagnostics, rulesDiagnostics];
	let setupProgress;
	let setupReady = false;
	let disposed = false;
	let callback;
	let watchTimer;
	let ruleNoticeTimer;
	let ruleNoticeOpen = false;
	const pendingActions = new Set();

	setupStatus.command = command("runSetup");
	setupStatus.text = "$(sync~spin) " + setupLabels.running;
	setupStatus.tooltip = "Preparing workspace providers. Click to reload.";
	setupStatus.show();
	checkStatus.command = command("check");
	checkStatus.tooltip = "CI compile and Bootstrap plan checks.";

	function finishSetupProgress() {
		setupProgress?.finish();
		setupProgress = undefined;
	}

	function beginProgress(title) {
		if (!title) return;
		let finish;
		const done = new Promise(resolve => { finish = resolve; });
		const current = { finish, reporter: undefined, percent: 0 };
		void Promise.resolve(vscode.window.withProgress({
			location: vscode.ProgressLocation.Notification,
			title,
			cancellable: false,
		}, reporter => {
			current.reporter = reporter;
			return done;
		})).catch(error => log(`[progress error] ${error.message}`));
		return current;
	}

	function showError(message, detail) {
		finishSetupProgress();
		setupStatus.text = "$(error) " + setupLabels.failed;
		setupStatus.tooltip = detail || message;
		output.appendLine(`[error] ${message}`);
		if (detail) output.appendLine(detail);
		output.show(true);
	}

	function updateDependencies(event = {}) {
		if (disposed) return;
		if (event.error || (event.exitCode !== undefined && event.exitCode !== 0)) {
			showError(event.message || setupLabels.failed, event.error || `Process exited with code ${event.exitCode}`);
			setupReady = false;
			return;
		}
		if (event.message) {
			const progress = Number.isFinite(event.completed) && Number.isFinite(event.total) ? ` ${event.completed}/${event.total}` : "";
			setupStatus.text = event.complete ? "$(check) " + setupLabels.passed : `$(sync~spin) ${event.message}${progress}`;
			setupStatus.tooltip = event.detail || event.message;
			if (setupProgress?.reporter && !event.complete) {
				const previous = setupProgress.percent;
				if (progress && event.total > 0) {
					setupProgress.percent = Math.max(previous, Math.min(100, 100 * event.completed / event.total));
				}
				setupProgress.reporter.report({ message: event.message + progress, increment: setupProgress.percent - previous });
			}
			output.appendLine(`${event.complete ? "[ready]" : "[setup]"} ${event.message}${event.detail ? `: ${event.detail}` : ""}`);
		}
		if (event.complete) {
			setupReady = true;
			finishSetupProgress();
			setupStatus.text = "$(check) " + setupLabels.passed;
			setupStatus.tooltip = "Click to rerun dependency setup and reload Luau LSP.";
		}
	}

	function publishCheck(kind, result = {}) {
		if (disposed) return;
		const check = checks[kind];
		const generation = Number(result.generation);
		if (Number.isFinite(generation) && generation < check.generation) return;
		if (Number.isFinite(generation)) check.generation = generation;
		check.progress?.finish();
		check.progress = undefined;
		const { status: checkStatus, diagnostics } = check;
		const checkLabels = check.config.status;
		const dirty = new Set(vscode.workspace.textDocuments.filter(document => document.isDirty && isInWorkspace(document.uri)).map(document => document.uri.toString()));
		const byFile = new Map();
		if (kind === "rules") actionSources.clear();
		const items = Array.isArray(result.findings) ? result.findings : [];
		for (const finding of items) {
			if (!finding || typeof finding.file !== "string") continue;
			const uri = path.isAbsolute(finding.file) ? vscode.Uri.file(finding.file) : vscode.Uri.file(asAbsolutePath(finding.file));
			if (dirty.has(uri.toString())) continue;
			const startLine = Math.max(0, Number(finding.line || 1) - 1);
			const startColumn = Math.max(0, Number(finding.column || 1) - 1);
			let range = new vscode.Range(startLine, startColumn, startLine, startColumn + 1);
			let sourceText;
			if (finding.rule && Number.isInteger(finding.endLine) && Number.isInteger(finding.endColumn)) {
				try {
					sourceText = fs.readFileSync(uri.fsPath, "utf8");
					if (finding.sourceHash && crypto.createHash("sha256").update(sourceText).digest("hex") !== finding.sourceHash) continue;
					const lines = sourceText.split(/\r?\n/);
					const column = (line, byte) => Buffer.from(lines[line] || "").subarray(0, Math.max(0, byte)).toString("utf8").length;
					const toRange = span => new vscode.Range(span.line - 1, column(span.line - 1, span.column - 1), span.endLine - 1, column(span.endLine - 1, span.endColumn - 1));
					range = toRange(finding);
					finding.relatedRanges = Array.isArray(finding.related) ? finding.related.map(toRange) : undefined;
				} catch { continue; }
			}
			const diagnostic = new vscode.Diagnostic(
				range,
				`${finding.fixture ? "Expected: " : ""}${finding.message || "Check failed"}`,
				(finding.severity === "information") ? vscode.DiagnosticSeverity.Information : finding.severity === "warning" ? vscode.DiagnosticSeverity.Warning : vscode.DiagnosticSeverity.Error,
			);
			diagnostic.source = finding.fixture ? "Rule fixture" : kind === "rules" && finding.rule ? "Rules" : finding.source || (kind === "rules" ? "Rules" : "Preflight");
			if (finding.rule) {
				diagnostic.code = { value: path.posix.basename(finding.rule), target: vscode.Uri.file(asAbsolutePath(finding.ruleDoc || finding.rule + "/README.md")) };
				if (finding.relatedRanges) diagnostic.relatedInformation = finding.relatedRanges.map(related => new vscode.DiagnosticRelatedInformation(new vscode.Location(uri, related), "Static assignment"));
				if (sourceText !== undefined && !finding.fixture && crypto.createHash("sha256").update(sourceText).digest("hex") === finding.sourceHash) {
					const key = uri.toString() + ":" + diagnostic.code.value + ":" + range.start.line + ":" + range.start.character;
					actionSources.set(key, sourceText);
				}
			}
			const key = uri.toString();
			if (!byFile.has(key)) byFile.set(key, { uri, diagnostics: [] });
			byFile.get(key).diagnostics.push(diagnostic);
		}
		diagnostics.clear();
		if (kind === "compile") compileFindings.clear();
		for (const [key, { uri, diagnostics: fileDiagnostics }] of byFile) {
			if (kind === "compile") {
				compileFindings.set(key, { uri, items: fileDiagnostics, visible: undefined });
				refreshCompileDiagnostics(uri);
			} else diagnostics.set(uri, fileDiagnostics);
		}
		if (result.error) {
			output.appendLine(`[check error] ${result.error}`);
			output.show(true);
		}
		if (!checkStatus) return;
		const workspaceItems = items.filter(item => !item.fixture && !item.editorTool);
		if (result.error) {
			checkStatus.text = checkLabels.failed;
			checkStatus.tooltip = result.error;
		} else if (workspaceItems.some(item => item.severity === "error")) {
			checkStatus.text = checkLabels.failed;
			checkStatus.tooltip = `${workspaceItems.filter(item => item.severity === "error").length} error(s); click to rerun checks`;
		} else if (workspaceItems.length) {
			checkStatus.text = checkLabels.warning;
			checkStatus.tooltip = `${workspaceItems.length} warning(s); click to rerun checks`;
		} else if (setupReady) {
			checkStatus.text = checkLabels.passed;
			checkStatus.tooltip = "CI compile and Bootstrap plan checks passed. Click to rerun.";
		}
		if (checkStatus.text) checkStatus.show();
	}

	function refreshCompileDiagnostics(uri) {
		const entry = compileFindings.get(uri.toString());
		if (!entry) return;
		const signature = item => {
			const line = item.range.start?.line ?? item.range.startLine;
			const column = item.range.start?.character ?? item.range.startCharacter;
			const message = item.message.replace(/^(?:TypeError|SyntaxError):\s*/, "").replace(/\s+/g, " ").trim();
			return JSON.stringify([line, column, message]);
		};
		const native = new Set((vscode.languages.getDiagnostics?.(uri) || []).filter(item => item.source === "Luau").map(signature));
		const analyzer = new Set(entry.items.filter(item => item.source === "Luau LSP workspace").map(signature));
		const visible = entry.items.filter(item => {
			if (item.source === "Luau LSP workspace") return !native.has(signature(item));
			if (item.source === "Lute") return !native.has(signature(item)) && !analyzer.has(signature(item));
			return true;
		});
		if (entry.visible?.length === visible.length && visible.every((item, index) => item === entry.visible[index])) return;
		entry.visible = visible;
		diagnostics.set(entry.uri, visible);
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
		pendingActions.add(action);
		if (watchTimer) clearTimeout(watchTimer);
		watchTimer = setTimeout(() => {
			watchTimer = undefined;
			const compile = pendingActions.has("compile");
			const checkAll = pendingActions.has("check") || (compile && pendingActions.has("rules"));
			const nextAction = pendingActions.has("run") ? "run" : checkAll ? "check" : compile ? "compile" : "rules";
			pendingActions.clear();
			if (!disposed) dispatch(nextAction);
		}, 350);
	}
	function startWatching(controllerCallback) {
		callback = controllerCallback;
		if (vscode.languages.onDidChangeDiagnostics) owned.push(vscode.languages.onDidChangeDiagnostics(({ uris }) => {
			for (const uri of uris) refreshCompileDiagnostics(uri);
		}));
		for (const { uri } of compileFindings.values()) refreshCompileDiagnostics(uri);
		const changed = new Set();
		const isRuleFixture = relative => /^rules\/.*\/tests\/(valid|invalid|review)\/.*\.luau$/.test(relative);
		const isRuleInput = relative => relative.startsWith("rules/luau/") ||
			relative === ".vscode/config/rules.json" || relative === ".vscode/config/rules.schema.json";
		const watchedPath = uri => {
			if (uri.scheme !== "file" || !isInWorkspace(uri)) return undefined;
			const relative = path.relative(root, uri.fsPath).split(path.sep).join("/");
			if (/^rules\/.*\/examples\//.test(relative)) return undefined;
			return workflow.watch.paths.some(glob => path.posix.matchesGlob(relative, glob)) ? relative : undefined;
		};
		owned.push(vscode.workspace.onDidChangeTextDocument(({ document, contentChanges }) => {
			const relative = watchedPath(document.uri);
			if (relative && document.isDirty && contentChanges.length) {
				changed.add(relative);
				compileFindings.delete(document.uri.toString());
				diagnostics.delete(document.uri);
				rulesDiagnostics.delete(document.uri);
			}
		}));
		// Disk events also cover edits made by Git, scripts, and external editors.
		const diskWatcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(workspaceFolder, "{**/*.luau,rules/luau/**,.vscode/config/rules.json,.vscode/config/rules.schema.json}"));
		const onDiskChange = uri => {
			const relative = watchedPath(uri);
			if (!relative || disposed) return;
			if (!isRuleInput(relative)) {
				if (relative.endsWith(".luau") && !relative.split("/").some(segment => ["node_modules", "build", "generated", "vendor", "examples"].includes(segment))) {
					schedule("check");
				}
				return;
			}
			if (relative.endsWith(".luau")) schedule("compile");
			if (workflow.rules.autoRefresh === true || isRuleFixture(relative)) {
				schedule("rules");
				return;
			}
			if (ruleNoticeOpen) return;
			clearTimeout(ruleNoticeTimer);
			ruleNoticeTimer = setTimeout(async () => {
				ruleNoticeTimer = undefined;
				ruleNoticeOpen = true;
				try {
					const action = await vscode.window.showInformationMessage("Repository rules updated. Refresh to apply the changes.", "Refresh Rules");
					if (!disposed && action === "Refresh Rules") dispatch("rules");
				} catch (error) {
					log(`[rules notification error] ${error.message}`);
				} finally {
					ruleNoticeOpen = false;
				}
			}, 350);
		};
		owned.push(diskWatcher, diskWatcher.onDidCreate(onDiskChange), diskWatcher.onDidChange(onDiskChange), diskWatcher.onDidDelete(onDiskChange));
		owned.push(vscode.workspace.onDidSaveTextDocument(document => {
			const relative = watchedPath(document.uri);
			if (!relative || !changed.delete(relative)) return;
			if (isRuleInput(relative)) onDiskChange(document.uri);
			else schedule(setupFiles.has(relative) ? "run" : "check");
		}));
		owned.push(vscode.workspace.onDidCloseTextDocument(document => {
			changed.delete(watchedPath(document.uri));
		}));
		owned.push(...registerRuleActions({ vscode, root, workflow, actionSources, command }));
		owned.push(registerRuleSettings({ vscode, workspaceFolder, root }));
		owned.push(vscode.commands.registerCommand(command("showOutput"), () => output.show(true)));
		owned.push(vscode.commands.registerCommand(command("runSetup"), () => dispatch("reloadProviders")));
		owned.push(vscode.commands.registerCommand(command("check"), () => dispatch("compile")));
		owned.push(vscode.commands.registerCommand(command("rules"), () => dispatch("rules")));
		return { dispose() { callback = undefined; } };
	}

	async function reloadLanguageServer() {
		try {
			if (vscode.extensions?.getExtension("JohnnyMorganz.luau-lsp")) {
				await vscode.commands.executeCommand("luau-lsp.reloadServer");
			}
		} catch (error) {
			log(`[provider reload error] ${error.message}`);
			output.show(true);
		}
	}

	function beginCheck(kind, generation) {
		const check = checks[kind];
		if (disposed || generation < check.generation) return false;
		check.generation = generation;
		check.progress?.finish();
		check.progress = beginProgress(check.config.notification);
		return true;
	}

	const api = {
		reloadLanguageServer,
		getLuauTools() {
			const config = section => vscode.workspace.getConfiguration(section, workspaceFolder.uri);
			const executable = name => process.platform === "win32" ? name + ".exe" : name;
			const extension = vscode.extensions.getExtension("JohnnyMorganz.luau-lsp");
			const extensionPath = extension?.extensionPath;
			const lsp = config("luau-lsp");
			const settings = {
				"luau-lsp.platform.type": lsp.get("platform.type", "standard"),
				"luau-lsp.fflags.enableNewSolver": lsp.get("fflags.enableNewSolver", true),
			};
			for (const group of [extension?.packageJSON?.contributes?.configuration].flat().filter(Boolean)) {
				for (const key of Object.keys(group.properties || {})) {
					if (/^luau-lsp\.(?:platform|types|diagnostics|fflags|plugins)\./.test(key)) settings[key] = lsp.get(key.slice("luau-lsp.".length));
				}
			}
			settings["luau-lsp.ignoreGlobs"] = lsp.get("ignoreGlobs", []);
			const resolve = (configured, installed, fallback) => configured
				? path.resolve(root, configured) : installed && fs.existsSync(installed) ? installed : fallback;
			return JSON.stringify({
				TEMPLATE_LUAU_ANALYZER: resolve(config("luau-lsp").get("server.path"), extensionPath && path.join(extensionPath, "bin", executable("server")), "luau-lsp"),
				TEMPLATE_LUAU_SETTINGS: JSON.stringify(settings),
				TEMPLATE_LUAU_BASE_CONFIG: lsp.get("server.baseLuaurc") || "",
				TEMPLATE_LUAU_SOURCEMAP: lsp.get("sourcemap.enabled") ? lsp.get("sourcemap.sourcemapFile", "sourcemap.json") : "",
			});
		},
		start: startWatching,
		run() { return dispatch("run"); },
		check() { return dispatch("check"); },
		updateDependencies,
		publishPreflight(result) { publishCheck("compile", result); },
		publishRules(result) { publishCheck("rules", result); },
		startWatching,
		showOutput() { output.show(true); },
		updateCheckProgress({ kind = "compile", generation, message }) {
			const check = checks[kind];
			if (!disposed && generation === check?.generation) check.progress?.reporter?.report({ message });
		},
		beginCheck(generation) { return beginCheck("compile", generation); },
		beginRules(generation) { return beginCheck("rules", generation); },
		beginSetup(generation) {
			if (disposed || Object.values(checks).some(check => generation < check.generation)) return false;
			setupReady = false;
			compileFindings.clear();
			for (const check of Object.values(checks)) {
				check.generation = generation;
				check.diagnostics.clear();
				check.progress?.finish();
				check.progress = undefined;
			}
			actionSources.clear();
			finishSetupProgress();
			setupProgress = beginProgress(workflow.dependencies.notification);
			return true;
		},
		log,
		dispose() {
			if (disposed) return;
			disposed = true;
			for (const check of Object.values(checks)) check.progress?.finish();
			finishSetupProgress();
			if (watchTimer) clearTimeout(watchTimer);
			clearTimeout(ruleNoticeTimer);
			for (const item of owned.reverse()) { try { item.dispose(); } catch { /* best-effort shutdown */ } }
		},
	};
	subscriptions.push(api);
	if (signal) signal.addEventListener("abort", api.dispose, { once: true });
	return api;
}

module.exports = { activate };
