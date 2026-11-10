"use strict";

const path = require("node:path");
const { spawn } = require("node:child_process");

const root = process.cwd();
const { connect } = require(path.join(__dirname, "../workbenchBridgeClient/index.js"));
const workflow = require("../../../../.vscode/config/workflow.json");

function parseFinding(line) {
	if (line.startsWith("::rule-finding::")) {
		try {
			const finding = JSON.parse(line.slice("::rule-finding::".length));
			return { ...finding, file: path.resolve(root, finding.file) };
		} catch { return undefined; }
	}
	const match = line.match(/^(.*?):(\d+):(\d+): (error|warning|information|info):(?: \[([^\]]+)\])? (.*)$/);
	if (!match) return undefined;
	return { file: match[1], line: Number(match[2]), column: Number(match[3]), severity: match[4] === "info" ? "information" : match[4], source: match[5] || "Preflight", editorTool: match[5] === "Luau LSP workspace", message: match[6] };
}

function runCommand([executable, ...args], { env = {}, onLine = () => {}, signal, input } = {}) {
	return new Promise((resolve, reject) => {
		if (signal?.aborted) return reject(new Error("Workspace client is closing"));
		const child = spawn(executable === "node" ? process.execPath : executable, args, { cwd: root, env: { ...process.env, ...env }, windowsHide: true, stdio: [input === undefined ? "ignore" : "pipe", "pipe", "pipe"] });
		if (child.stdin) {
			child.stdin.on("error", () => {});
			child.stdin.end(input);
		}
		child.stdout.setEncoding("utf8");
		child.stderr.setEncoding("utf8");
		let stdoutTail = "";
		let stderrTail = "";
		let stdoutText = "";
		let stderrText = "";
		const consume = (chunk, isError) => {
			const text = chunk.toString();
			const buffer = (isError ? stderrTail : stdoutTail) + text;
			if (isError) stderrText = (stderrText + text).slice(-512 * 1024);
			else stdoutText = (stdoutText + text).slice(-512 * 1024);
			const lines = buffer.split(/\r?\n/);
			const tail = lines.pop();
			if (isError) stderrTail = tail; else stdoutTail = tail;
			for (const line of lines) if (line) onLine(line, isError);
		};
		child.stdout.on("data", chunk => consume(chunk, false));
		child.stderr.on("data", chunk => consume(chunk, true));
		const cancel = () => {
			if (process.platform !== "win32" || !child.pid) { child.kill(); return; }
			const killer = spawn("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
			killer.once("error", () => child.kill());
			killer.once("close", code => { if (code !== 0) child.kill(); });
		};
		signal?.addEventListener("abort", cancel, { once: true });
		child.once("error", error => { signal?.removeEventListener("abort", cancel); reject(error); });
		child.once("close", code => {
			signal?.removeEventListener("abort", cancel);
			if (stdoutTail) onLine(stdoutTail, false);
			if (stderrTail) onLine(stderrTail, true);
			resolve({ code: code ?? 1, stdout: stdoutText, stderr: stderrText });
		});
	});
}

function createController(bridgeClient, bridgeModule, getLuauTools = async () => ({})) {
	const activeChecks = new Map();
	let generation = 0;
	let closing = false;
	let setupFlight;
	let dependenciesReady = false;
	const state = { dependenciesReady: false, preflightState: "pending", errorCount: 0, warningCount: 0, setupError: undefined, preflightError: undefined };
	const lifecycle = new AbortController();
	const report = (method, value) => {
		if (closing) return Promise.resolve(undefined);
		return bridgeClient.call({ target: bridgeModule, path: [method], args: [value] }).catch(error => {
			if (closing) return undefined;
			throw error;
		});
	};
	const reportDetached = (method, value) => {
		void report(method, value).catch(error => {
			if (closing || method === "log") return;
			void report("log", `[bridge report error] ${error instanceof Error ? error.message : String(error)}`).catch(() => {});
		});
	};

	async function setup() {
		await report("updateDependencies", { message: workflow.dependencies.status.running });
		let result;
		try {
			result = await runCommand(workflow.dependencies.command, {
			env: workflow.dependencies.env,
			signal: lifecycle.signal,
			onLine(line, isError) {
				if (line.startsWith("::workspace-setup::")) {
					try {
						const progress = JSON.parse(line.slice("::workspace-setup::".length));
						reportDetached("updateDependencies", { ...progress, complete: false });
					} catch { reportDetached("log", `Invalid setup progress: ${line}`); }
				} else reportDetached("log", `${isError ? "[setup error] " : "[setup] "}${line}`);
			},
			});
		} catch (caught) {
			dependenciesReady = false;
			const detail = caught instanceof Error ? caught.message : String(caught);
			state.dependenciesReady = false;
			state.preflightState = "blocked";
			state.setupError = detail;
			await report("updateDependencies", { error: detail, message: workflow.dependencies.status.failed });
			return false;
		}
		if (result.code !== 0) {
			dependenciesReady = false;
			const detail = result.stderr.trim() || result.stdout.trim() || `Setup exited with code ${result.code}`;
			state.dependenciesReady = false;
			state.preflightState = "blocked";
			state.setupError = detail;
			await report("updateDependencies", { error: detail, message: workflow.dependencies.status.failed, exitCode: result.code });
			return false;
		}
		dependenciesReady = true;
		state.dependenciesReady = true;
		state.setupError = undefined;
		await report("updateDependencies", { message: workflow.dependencies.status.passed, complete: true, completed: 1, total: 1 });
		return true;
	}

	function runSetup(reloadProviders = false, trigger = "manual") {
		if (setupFlight) return setupFlight;
		dependenciesReady = false;
		state.dependenciesReady = false;
		state.preflightState = "pending";
		state.setupError = undefined;
		const setupGeneration = ++generation;
		for (const check of activeChecks.values()) check.controller.abort();
		activeChecks.clear();
		setupFlight = (async () => {
			await report("beginSetup", { generation: setupGeneration, trigger });
			const ready = await setup();
			if (ready && reloadProviders) await report("reloadLanguageServer");
			if (ready) await checkAll(trigger);
			return ready;
		})().finally(() => { setupFlight = undefined; });
		return setupFlight;
	}

	async function check(kind = "compile", trigger = "manual") {
		const rules = kind === "rules";
		if (closing || !dependenciesReady) return;
		activeChecks.get(kind)?.controller.abort();
		const controller = new AbortController();
		const id = ++generation;
		activeChecks.set(kind, { controller, id });
		if (!rules) {
			state.preflightState = "running";
			state.preflightError = undefined;
		}
		await report(rules ? "beginRules" : "beginCheck", { generation: id, trigger });
		const findings = [];
		let error;
		try {
			const env = rules ? {} : await getLuauTools();
			const result = await runCommand((rules ? workflow.rules : workflow.checks).command, {
				env,
				signal: controller.signal,
				onLine(line, isError) {
					if (!isError && line.startsWith("::preflight-stage::")) {
						if (activeChecks.get(kind)?.id === id) reportDetached("updateCheckProgress", { kind, generation: id, message: line.slice("::preflight-stage::".length) });
						return;
					}
					const finding = !isError && parseFinding(line);
					if (finding) findings.push(finding);
					else reportDetached("log", `${isError ? "[check error] " : "[check] "}${line}`);
				},
			});
			if (result.code !== 0 && findings.length === 0) error = result.stderr.trim() || result.stdout.trim() || `Preflight exited with code ${result.code}`;
		} catch (caught) {
			if (!controller.signal.aborted) error = caught instanceof Error ? caught.message : String(caught);
		}
		if (!closing && !controller.signal.aborted && activeChecks.get(kind)?.id === id) {
			const errorCount = findings.filter(finding => !finding.fixture && !finding.editorTool && finding.severity === "error").length + (error ? 1 : 0);
			const warningCount = findings.filter(finding => !finding.fixture && !finding.editorTool && finding.severity === "warning").length;
			const status = errorCount > 0 ? "failed" : warningCount > 0 ? "warning" : "passed";
			if (rules) {
				state.rulesState = status;
				state.ruleErrorCount = errorCount;
			} else {
				state.errorCount = errorCount;
				state.warningCount = warningCount;
				state.preflightError = error;
				state.preflightState = status;
			}
			await report(rules ? "publishRules" : "publishPreflight", { scope: "workspace", generation: id, findings, error });
		}
		if (activeChecks.get(kind)?.id === id) activeChecks.delete(kind);
	}

	async function checkFile(request) {
		const compile = request.kind === "compile";
		const key = request.candidate ? Symbol(request.file) : (compile ? "compile:" : "file:") + request.file;
		activeChecks.get(key)?.controller.abort();
		if (request.cancel || closing || !dependenciesReady) return;
		const controller = new AbortController();
		activeChecks.set(key, { controller });
		const findings = [];
		let incomplete = false;
		try {
			const result = await runCommand(compile ? [...workflow.checks.command, "--compile-file"] : [...workflow.rules.command, "--rule-file"], {
				input: JSON.stringify(request),
				signal: controller.signal,
				onLine(line, isError) {
					if (isError) return;
					if (line === "::rule-incomplete::") incomplete = true;
					const finding = parseFinding(line);
					if (finding) findings.push(finding);
				},
			});
			if (controller.signal.aborted) return;
			const failed = findings.some(item => compile ? path.resolve(root, item.file) !== path.resolve(root, request.file) : item.checkerFailure || !item.rule) ||
				(result.code !== 0 && !findings.length);
			return { scope: "file", findings, incomplete, failed };
		} finally {
			if (activeChecks.get(key)?.controller === controller) activeChecks.delete(key);
		}
	}

	async function checkAll(trigger) {
		await Promise.all([check("compile", trigger), check("rules", trigger)]);
	}

	return {
		async start() { const ready = await runSetup(false, "startup"); return ready; },
		run: trigger => runSetup(false, trigger),
		reloadProviders: trigger => runSetup(true, trigger),
		check,
		checkFile,
		checkAll,
		getState() { return { ...state }; },
		close() {
			if (closing) return;
			closing = true;
			lifecycle.abort();
			for (const check of activeChecks.values()) check.controller.abort();
			bridgeClient.close?.();
		},
	};
}

async function main() {
	let bridgeClient;
	let controller;
	try {
		bridgeClient = await connect({ sessionFile: require("./session.cjs").selectedSession(root), workspace: root });
		if (process.argv.includes("--problems")) {
			const module = await bridgeClient.loadModule({ path: "dependencies/packages/editor/editorIntegration/problems.cjs" });
			const problems = await bridgeClient.call({ target: module, path: ["snapshot"], args: [] });
			console.log(JSON.stringify(await bridgeClient.snapshot({ target: problems }), null, 2));
			return;
		}
		bridgeClient.onClose(() => controller?.close());
		const bridgeModule = await bridgeClient.loadModule({ path: "dependencies/packages/editor/editorIntegration/host.cjs" });
		controller = createController(bridgeClient, bridgeModule, async () =>
			JSON.parse(await bridgeClient.call({ target: bridgeModule, path: ["getLuauTools"], args: [] })));
		await bridgeClient.call({
			target: bridgeModule,
			path: ["start"],
			args: [(action, trigger) => {
				if (action === "file") return controller.checkFile(JSON.parse(trigger));
				const run = action === "reloadProviders" ? controller.reloadProviders(trigger)
					: action === "run" ? controller.run(trigger)
					: action === "check" ? controller.checkAll(trigger) : controller.check(action, trigger);
				void Promise.resolve(run).catch(error => {
					void bridgeClient.call({ target: bridgeModule, path: ["log"], args: [`[controller error] ${error instanceof Error ? error.message : String(error)}`] }).catch(() => {});
				});
			}],
		});
		await controller.start();
		if (process.env.WORKBENCH_BRIDGE_ONCE === "1") {
			const state = controller.getState();
			const success = state.dependenciesReady && ["passed", "warning"].includes(state.preflightState);
			console.log(`${success ? "WORKSPACE_READY" : "WORKSPACE_FAILED"} ${JSON.stringify(state)}`);
			if (!success) process.exitCode = 1;
			controller.close();
			await bridgeClient.closed;
			return;
		}
		await bridgeClient.closed;
	} finally {
		if (controller) controller.close();
		else bridgeClient?.close?.();
	}
}

if (require.main === module) {
	main().catch(error => {
		console.error(error instanceof Error ? error.stack || error.message : error);
		process.exitCode = 1;
	});
}

module.exports = { createController, parseFinding, runCommand };
