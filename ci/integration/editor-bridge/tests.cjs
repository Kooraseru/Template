"use strict";

// Run with VS Code's existing executable in ELECTRON_RUN_AS_NODE mode.
// This mocks the editor API; it does not create workflow History or run act.
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");

async function main() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "template-editor-bridge-"));
  let tick;
  let count = 0;
  const commands = [];
  const subscriptions = [];
  const folder = { uri: { scheme: "file", fsPath: root } };
  const source = "name: CI\njobs: {}\n";
  const vscode = {
    workspace: { isTrusted: true, workspaceFolders: [folder] },
    window: { createOutputChannel: () => ({ appendLine() {}, dispose() {} }) },
    Uri: { file: fsPath => ({ fsPath }) },
    extensions: { getExtension: () => ({ activate: async () => {} }) },
    commands: { executeCommand: async (...args) => { commands.push(args); } },
    tasks: { taskExecutions: [], onDidStartTask() {}, onDidEndTask() {} },
  };
  try {
    await fs.mkdir(path.join(root, ".github/workflows"), { recursive: true });
    for (const file of ["ci.yml", "template.yml"]) await fs.writeFile(path.join(root, ".github/workflows", file), source);
    const context = { process, module: { exports: {} }, require: name => name === "vscode" ? vscode : require(name),
      setInterval: callback => { tick = callback; }, clearInterval() {} };
    vm.runInNewContext(await fs.readFile(path.join(__dirname, "extension.cjs"), "utf8"), context);
    await context.module.exports.activate({ subscriptions, globalStorageUri: { fsPath: path.join(root, "storage/bridge") } });
    const mailbox = path.join(root, "build/runtime/local-actions");
    const session = JSON.parse(await fs.readFile(path.join(mailbox, "session.json"), "utf8"));
    async function request(fields) {
      const id = (++count).toString(16).padStart(32, "0");
      await fs.writeFile(path.join(mailbox, id + ".request.json"), JSON.stringify({ token: session.token, ...fields }));
      tick();
      for (let attempt = 0; attempt < 200; attempt++) {
        const response = await fs.readFile(path.join(mailbox, id + ".response.json"), "utf8").catch(() => null);
        if (response) return JSON.parse(response);
        await new Promise(resolve => setTimeout(resolve, 5));
      }
      throw new Error("Mock bridge did not respond");
    }
    const selection = { operation: "start", workflow: "template.yml", source, definition: { name: "Template conformance", jobs: {} } };
    const outside = await request({ ...selection, workflow: "../outside.yml" });
    assert.equal(outside.ok, false);
    assert.match(outside.error, /workflow filename/);
    const stale = await request({ ...selection, source: "stale" });
    assert.equal(stale.ok, false);
    assert.match(stale.error, /changed before execution/);
    assert.equal(commands.length, 0);
    assert.equal((await request(selection)).ok, true);
    assert.equal(commands.length, 1);
    assert.equal(commands[0][0], "githubLocalActions.runWorkflow");
    assert.equal(commands[0][1].workflow.uri.fsPath, path.join(root, ".github/workflows/template.yml"));
    assert.equal(commands[0][1].workflow.yaml.name, "Template conformance");
    const overlapping = await request(selection);
    assert.equal(overlapping.ok, false);
    assert.match(overlapping.error, /already active/);
    assert.equal(commands.length, 1);
    assert.equal((await request({ operation: "status" })).ok, true);
  } finally {
    for (const subscription of subscriptions) if (subscription?.dispose) subscription.dispose();
    // Only this newly created temporary test directory is removed.
    assert.equal(path.dirname(path.resolve(root)), path.resolve(os.tmpdir()));
    assert(path.basename(root).startsWith("template-editor-bridge-"));
    await fs.rm(root, { recursive: true, force: true });
  }
}

main().then(() => console.log("Editor bridge tests passed.")).catch(error => { console.error(error); process.exit(1); });
