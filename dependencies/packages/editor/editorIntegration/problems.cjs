"use strict";

const path = require("node:path");

function activate({ vscode, workspaceFolder }) {
	const root = workspaceFolder.uri.fsPath;
	return {
		snapshot() {
			const problems = [];
			for (const [uri, diagnostics] of vscode.languages.getDiagnostics()) {
				if (uri.scheme !== "file") continue;
				const relative = path.relative(root, uri.fsPath);
				if (!relative || relative === ".." || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)) continue;
				for (const { range, message, severity, source, code } of diagnostics) {
					problems.push({
						file: relative.split(path.sep).join("/"),
						line: range.start.line + 1,
						column: range.start.character + 1,
						endLine: range.end.line + 1,
						endColumn: range.end.character + 1,
						severity: ["error", "warning", "information", "hint"][severity],
						source,
						code: typeof code === "object" ? code.value : code,
						message,
					});
				}
			}
			return problems;
		},
	};
}

module.exports = { activate };
