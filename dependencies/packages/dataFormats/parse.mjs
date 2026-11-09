import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";
const require = createRequire(import.meta.url);
const root = path.resolve(
	path.dirname(fileURLToPath(import.meta.url)),
	"../../..",
);
const [format, input] = process.argv.slice(2);
if (format === "toml") {
	const toml = require("../dependencyLoader/vendor/toml.cjs");
	process.stdout.write(JSON.stringify(toml.parse(input)));
} else if (format === "yaml") {
	const yaml = require(
		path.join(root, "build/dependencies/npm/node_modules/yaml/dist/index.js"),
	);
	process.stdout.write(JSON.stringify(yaml.parse(input)));
} else throw new Error(`Unsupported format: ${format}`);
