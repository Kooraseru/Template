"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "../../../..");
const config = fs.readFileSync(path.join(root, ".vscode/config/act/actrc"), "utf8");
const args = config.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith("#"));
const result = spawnSync("act", [...args, ...process.argv.slice(2)], { cwd: root, stdio: "inherit" });
if (result.error) console.error(result.error.message);
process.exitCode = result.status ?? 1;
