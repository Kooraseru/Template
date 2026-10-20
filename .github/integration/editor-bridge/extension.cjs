"use strict";

const vscode = require("vscode");
const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");

// This adapter runs only in VS Code's existing extension host.
// No child processes, arbitrary commands, editor focus, or simulated input.
async function activate(context) {
  if (!vscode.workspace.isTrusted) return;
  const folders = (vscode.workspace.workspaceFolders || []).filter(f => f.uri.scheme === "file");
  const output = vscode.window.createOutputChannel("Local Actions Command Bridge");
  context.subscriptions.push(output);
  const completed = new Map();
  const active = new Map();
  const states = [];
  let disposed = false;
  function owned(task) { return task.definition.type === "GitHub Local Actions"; }
  function record(execution, running) {
    if (!owned(execution.task)) return;
    const task = execution.task;
    const scope = task.scope;
    const item = {
      name: task.name,
      workspace: scope && scope.uri ? scope.uri.fsPath : null,
      log: task.definition.logPath || null,
      running,
    };
    if (running) {
      active.set(execution, item);
      for (const state of states) if (state.folder.uri.fsPath === item.workspace) state.startingUntil = 0;
    }
    else {
      active.delete(execution);
      completed.set(item.log || item.name, item);
      if (completed.size > 64) completed.delete(completed.keys().next().value);
    }
  }
  for (const execution of vscode.tasks.taskExecutions) record(execution, true);
  context.subscriptions.push(vscode.tasks.onDidStartTask(e => record(e.execution, true)));
  context.subscriptions.push(vscode.tasks.onDidEndTask(e => record(e.execution, false)));

  for (const folder of folders) {
    if (!await fs.stat(path.join(folder.uri.fsPath, ".github/workflows/ci.yml")).catch(() => null)) continue;
    const root = path.join(folder.uri.fsPath, ".kero/.runtime/local-actions");
    await fs.mkdir(root, { recursive: true });
    const state = { folder, root, token: crypto.randomBytes(32).toString("hex"), seen: new Set(), busy: false, startingUntil: 0 };
    states.push(state);
    await fs.writeFile(path.join(root, "session.json"), JSON.stringify({
      token: state.token, workspace: folder.uri.fsPath, pid: process.pid,
      operations: ["status", "start"],
    }), { mode: 0o600 });
  }

  async function poll(state) {
    if (state.busy || disposed) return;
    state.busy = true;
    try {
      const session = JSON.parse(await fs.readFile(path.join(state.root, "session.json"), "utf8"));
      if (session.token !== state.token) return;
      for (const name of await fs.readdir(state.root)) {
        if (!/^[a-f0-9]{32}\.request\.json$/.test(name) || state.seen.has(name)) continue;
        state.seen.add(name);
        const response = path.join(state.root, name.replace(".request.", ".response."));
        let result;
        try {
          const bytes = await fs.readFile(path.join(state.root, name));
          if (bytes.length > 4096) throw new Error("Request exceeds limit");
          const request = JSON.parse(bytes);
          if (request.token !== state.token) throw new Error("Stale or unauthorized bridge session");
          if (Object.keys(request).some(k => !["token", "operation"].includes(k))) throw new Error("Unknown request field");
          if (!["status", "start"].includes(request.operation)) throw new Error("Unsupported operation");
          const before = [...active.values()].filter(t => t.workspace === state.folder.uri.fsPath);
          if (request.operation === "start") {
            if (before.length || Date.now() < state.startingUntil) throw new Error("A GitHub Local Actions run is already active in this workspace");
            const workflows = (await fs.readdir(path.join(state.folder.uri.fsPath, ".github/workflows")))
              .filter(n => /\.ya?ml$/.test(n));
            if (workflows.length !== 1 || workflows[0] !== "ci.yml") throw new Error("Expected exactly one workflow: ci.yml");
            const extension = vscode.extensions.getExtension("SanjulaGanepola.github-local-actions");
            if (!extension) throw new Error("GitHub Local Actions is not installed");
            await extension.activate();
            state.startingUntil = Date.now() + 15000;
            try {
              await vscode.commands.executeCommand("githubLocalActions.runAllWorkflows", { workspaceFolder: state.folder });
            } catch (error) { state.startingUntil = 0; throw error; }
          }
          result = { ok: true, logsDirectory: path.join(path.dirname(context.globalStorageUri.fsPath), "sanjulaganepola.github-local-actions"), starting: Date.now() < state.startingUntil, tasks: [...active.values(), ...completed.values()]
            .filter(t => t.workspace === state.folder.uri.fsPath) };
        } catch (error) { result = { ok: false, error: String(error.message || error) }; }
        await fs.writeFile(response + ".tmp", JSON.stringify(result));
        await fs.rename(response + ".tmp", response);
      }
    } finally { state.busy = false; }
  }
  const timer = setInterval(() => {
    for (const state of states) poll(state).catch(error => output.appendLine(String(error)));
  }, 500);
  context.subscriptions.push({ dispose() {
    disposed = true;
    clearInterval(timer);
    for (const state of states) {
      const file = path.join(state.root, "session.json");
      fs.readFile(file, "utf8").then(bytes => {
        if (JSON.parse(bytes).token === state.token) return fs.unlink(file);
      }).catch(() => {});
    }
  }});
}

module.exports = { activate };
