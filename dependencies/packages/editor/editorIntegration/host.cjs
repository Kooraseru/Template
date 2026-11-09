"use strict";

const path = require("node:path");

function activate(context) {
	// The bridge can restart while VS Code keeps its CommonJS module cache.
	const directory = path.resolve(__dirname) + path.sep;
	for (const file of Object.keys(require.cache)) {
		if (file.startsWith(directory) && file !== __filename) delete require.cache[file];
	}
	return require("./activate.cjs").activate(context);
}

module.exports = { activate };
