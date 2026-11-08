"use strict";

const path = require("node:path");
const { spawn } = require("node:child_process");

const root = process.cwd();
const { connect } = require(path.join(__dirname, "../workbenchBridgeClient/index.js"));
const workflow = require("../../../.vscode/config/workflow.json");

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

function runCommand([executable, ...args], { env = {}, onLine = () => {}, signal } = {}) {
	return new Promise((resolve, reject) => {
		if (signal?.aborted) return reject(new Error("Workspace client is closing"));
		const child = spawn(executable === "node" ? process.execPath : executable, args, { cwd: root, env: { ...process.env, ...env }, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
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

	function runSetup(reloadProviders = false) {
		if (setupFlight) return setupFlight;
		dependenciesReady = false;
		state.dependenciesReady = false;
		state.preflightState = "pending";
		state.setupError = undefined;
		const setupGeneration = ++generation;
		for (const check of activeChecks.values()) check.controller.abort();
		activeChecks.clear();
		setupFlight = (async () => {
			await report("beginSetup", setupGeneration);
			const ready = await setup();
			if (ready && reloadProviders) await report("reloadLanguageServer");
			if (ready) await checkAll();
			return ready;
		})().finally(() => { setupFlight = undefined; });
		return setupFlight;
	}

	async function check(kind = "compile") {
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
		await report(rules ? "beginRules" : "beginCheck", id);
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
			await report(rules ? "publishRules" : "publishPreflight", { generation: id, findings, error });
		}
		if (activeChecks.get(kind)?.id === id) activeChecks.delete(kind);
	}

	async function checkAll() {
		await Promise.all([check("compile"), check("rules")]);
	}

	return {
		async start() { const ready = await runSetup(); return ready; },
		run: runSetup,
		reloadProviders: () => runSetup(true),
		check,
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
		bridgeClient = await connect({ sessionFile: process.env.WORKBENCH_BRIDGE_SESSION, workspace: root });
		if (process.argv.includes("--problems")) {
			const module = await bridgeClient.loadModule({ path: "dependencies/packages/editorIntegration/problems.cjs" });
			const problems = await bridgeClient.call({ target: module, path: ["snapshot"], args: [] });
			console.log(JSON.stringify(await bridgeClient.snapshot({ target: problems }), null, 2));
			return;
		}
		bridgeClient.onClose(() => controller?.close());
		const bridgeModule = await bridgeClient.loadModule({ path: "dependencies/packages/editorIntegration/activate.cjs" });
		controller = createController(bridgeClient, bridgeModule, async () =>
			JSON.parse(await bridgeClient.call({ target: bridgeModule, path: ["getLuauTools"], args: [] })));
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
		await bridgeClient.call({
			target: bridgeModule,
			path: ["start"],
			args: [action => {
				const run = action === "reloadProviders" ? controller.reloadProviders()
					: action === "run" ? controller.run()
					: action === "check" ? controller.checkAll() : controller.check(action);
				void Promise.resolve(run).catch(error => {
					void bridgeClient.call({ target: bridgeModule, path: ["log"], args: [`[controller error] ${error instanceof Error ? error.message : String(error)}`] }).catch(() => {});
				});
			}],
		});
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
