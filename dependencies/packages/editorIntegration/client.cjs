"use strict";

const path = require("node:path");
const { spawn } = require("node:child_process");

const root = process.cwd();
const { connect } = require(path.join(__dirname, "../workbenchBridgeClient/index.js"));
const SETUP = "dependencies/packages/dependencyLoader/index.ts";
const CHECKER = "dependencies/packages/preflightChecker/index.ts";

function parseFinding(line) {
	const match = line.match(/^(.*?):(\d+):(\d+): (error|warning|information|info):(?: \[([^\]]+)\])? (.*)$/);
	if (!match) return undefined;
	return { file: match[1], line: Number(match[2]), column: Number(match[3]), severity: match[4] === "info" ? "information" : match[4], source: match[5] || "Preflight", message: match[6] };
}

function runNode(script, { env = {}, onLine = () => {}, signal } = {}) {
	return new Promise((resolve, reject) => {
		if (signal?.aborted) return reject(new Error("Workspace client is closing"));
		const child = spawn(process.execPath, [script], { cwd: root, env: { ...process.env, ...env }, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
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

function createController(bridgeClient, bridgeModule) {
	let activeCheck;
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
		await report("updateDependencies", { message: "Loading dependencies" });
		let result;
		try {
			result = await runNode(SETUP, {
			env: { VSCODE_WORKSPACE_SETUP: "1" },
			signal: lifecycle.signal,
			onLine(line, isError) {
				if (line.startsWith("::workspace-setup::")) {
					try {
						const progress = JSON.parse(line.slice("::workspace-setup::".length));
						reportDetached("updateDependencies", { ...progress, complete: progress.completed === progress.total });
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
			await report("updateDependencies", { error: detail, message: "Dependency setup failed" });
			return false;
		}
		if (result.code !== 0) {
			dependenciesReady = false;
			const detail = result.stderr.trim() || result.stdout.trim() || `Setup exited with code ${result.code}`;
			state.dependenciesReady = false;
			state.preflightState = "blocked";
			state.setupError = detail;
			await report("updateDependencies", { error: detail, message: "Dependency setup failed", exitCode: result.code });
			return false;
		}
		dependenciesReady = true;
		state.dependenciesReady = true;
		state.setupError = undefined;
		await report("updateDependencies", { message: "Dependencies ready", complete: true, completed: 1, total: 1 });
		return true;
	}

	function runSetup() {
		if (setupFlight) return setupFlight;
		dependenciesReady = false;
		state.dependenciesReady = false;
		state.preflightState = "pending";
		state.setupError = undefined;
		const setupGeneration = ++generation;
		activeCheck?.controller.abort();
		activeCheck = undefined;
		setupFlight = (async () => {
			await report("beginSetup", setupGeneration);
			const ready = await setup();
			if (ready) await check();
			return ready;
		})().finally(() => { setupFlight = undefined; });
		return setupFlight;
	}

	async function check() {
		if (closing || !dependenciesReady) return;
		if (activeCheck) activeCheck.controller.abort();
		const controller = new AbortController();
		const id = ++generation;
		activeCheck = { controller, id };
		state.preflightState = "running";
		state.preflightError = undefined;
		await report("beginCheck", id);
		const findings = [];
		let error;
		try {
			const result = await runNode(CHECKER, {
				signal: controller.signal,
				onLine(line, isError) {
					const finding = !isError && parseFinding(line);
					if (finding) findings.push(finding);
					else reportDetached("log", `${isError ? "[check error] " : "[check] "}${line}`);
				},
			});
			if (result.code !== 0 && findings.length === 0) error = result.stderr.trim() || result.stdout.trim() || `Preflight exited with code ${result.code}`;
		} catch (caught) {
			if (!controller.signal.aborted) error = caught instanceof Error ? caught.message : String(caught);
		}
		if (!closing && !controller.signal.aborted && id === generation) {
			state.errorCount = findings.filter(finding => finding.severity === "error").length + (error ? 1 : 0);
			state.warningCount = findings.filter(finding => finding.severity === "warning").length;
			state.preflightError = error;
			state.preflightState = error || state.errorCount > 0 ? "failed" : state.warningCount > 0 ? "warning" : "passed";
			await report("publishPreflight", { generation: id, findings, error });
		}
		if (activeCheck?.id === id) activeCheck = undefined;
	}

	return {
		async start() { const ready = await runSetup(); return ready; },
		run: runSetup,
		check,
		getState() { return { ...state }; },
		close() {
			if (closing) return;
			closing = true;
			lifecycle.abort();
			activeCheck?.controller.abort();
			bridgeClient.close?.();
		},
	};
}

async function main() {
	let bridgeClient;
	let controller;
	try {
		bridgeClient = await connect({ sessionFile: process.env.WORKBENCH_BRIDGE_SESSION, workspace: root });
		bridgeClient.onClose(() => controller?.close());
		const bridgeModule = await bridgeClient.loadModule({ path: "dependencies/packages/editorIntegration/activate.cjs" });
		controller = createController(bridgeClient, bridgeModule);
		await controller.start();
		await bridgeClient.call({
			target: bridgeModule,
			path: ["start"],
			args: [action => {
				void Promise.resolve(action === "run" ? controller.run() : controller.check()).catch(error => {
					void bridgeClient.call({ target: bridgeModule, path: ["log"], args: [`[controller error] ${error instanceof Error ? error.message : String(error)}`] }).catch(() => {});
				});
			}],
		});
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

module.exports = { createController, parseFinding, runNode };
