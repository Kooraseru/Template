"use strict";

const fs = require("node:fs");
const path = require("node:path");

const request = JSON.parse(fs.readFileSync(0, "utf8"));
const { action, options, stage, prerequisites, workspace, resolution } = request;
function failure(name) {
	if (fs.existsSync(path.join(workspace, name))) {
		console.error(name);
		process.exit(1);
	}
}

if (action === "resolve") {
	failure("fail-resolve-" + options.kind);
	const input = options.kind === "seed"
		? path.join(prerequisites["local.fixture"].source, "version")
		: prerequisites["tool.seed"].value;
	console.log(JSON.stringify({ resolution: { value: fs.readFileSync(input, "utf8") } }));
} else {
	failure("fail-install-" + options.kind);
	fs.mkdirSync(path.join(stage, "output"));
	const output = options.kind === "seed" ? "value" : "tool.cjs";
	const content = options.kind === "seed"
		? resolution.value
		: "console.log(" + JSON.stringify(fs.readFileSync(prerequisites["tool.seed"].value, "utf8")) + ", ...process.argv.slice(2));\n";
	fs.writeFileSync(path.join(stage, "output", output), content);
	console.log(JSON.stringify({
		outputs: [{ from: "output", to: options.target }],
		exports: {
			[options.kind === "seed" ? "value" : "cli"]: { root: "managed", path: options.target + "/" + output },
		},
		...(options.kind === "seed" ? {} : { executable: { export: "cli", interpreter: ["node"] } }),
	}));
}
