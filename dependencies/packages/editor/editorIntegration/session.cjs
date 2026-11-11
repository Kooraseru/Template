"use strict";
const fs = require("node:fs");
const path = require("node:path");

function selectedSession(root) {
	if (process.env.WORKBENCH_BRIDGE_SESSION) return process.env.WORKBENCH_BRIDGE_SESSION;
	const selection = path.join(root, ".workspace/editor-problems/session-file.txt");
	return fs.existsSync(selection) ? fs.readFileSync(selection, "utf8").trim() || undefined : undefined;
}
module.exports = { selectedSession };
