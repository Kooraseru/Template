"use strict";

const fs = require("node:fs");
const path = require("node:path");

function headerEdit(text, relative) {
	const first = text.split(/\r?\n/, 1)[0];
	const expected = "-- " + relative;
	if (first === expected) return undefined;
	if (/^-- (?:[^\s/]+\/)+[^\s/]+\.luau$/.test(first)) {
		return { length: first.length, text: expected };
	}
	if (first.startsWith("--") && !first.startsWith("--!")) return undefined;
	return { length: 0, text: expected + (text.includes("\r\n") ? "\r\n" : "\n") };
}

// This intentionally accepts a small, unambiguous subset of Luau literals.
function jsonObject(literal) {
	const token = /\s*([A-Za-z_][A-Za-z_0-9]*|"(?:[^"\\\r\n]|\\["\\nrt])*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?|[{},;=])/y;
	let offset = 0;
	let next;
	function advance() {
		token.lastIndex = offset;
		const match = token.exec(literal);
		if (!match && literal.slice(offset).trim()) throw new Error("Unsupported literal");
		next = match?.[1];
		if (match) offset = token.lastIndex;
	}
	function take(value) {
		if (next !== value) throw new Error("Unexpected token");
		advance();
	}
	function value(depth) {
		if (depth > 30) throw new Error("Object nesting limit");
		if (next === "{") return object(depth + 1);
		const raw = next;
		if (!raw || !/^(?:"|-?\d|true$|false$)/.test(raw)) throw new Error("Unsupported value");
		advance();
		const result = JSON.parse(raw);
		if (typeof result === "number" && (!Number.isFinite(result) || Math.abs(result) > Number.MAX_SAFE_INTEGER || Object.is(result, -0))) {
			throw new Error("Unsupported number");
		}
		return result;
	}
	function object(depth) {
		take("{");
		const result = Object.create(null);
		while (next !== "}") {
			const key = next;
			if (!key || !/^[A-Za-z_][A-Za-z_0-9]*$/.test(key) || Object.hasOwn(result, key)) throw new Error("Invalid key");
			advance();
			take("=");
			result[key] = value(depth);
			if (next === "," || next === ";") advance();
			else if (next !== "}") throw new Error("Expected separator");
		}
		take("}");
		if (!Object.keys(result).length) throw new Error("Ambiguous empty table");
		return result;
	}
	try {
		advance();
		const result = object(0);
		return next === undefined ? result : undefined;
	} catch { return undefined; }
}

function registerRuleActions({ vscode, root, workflow, actionSources, command }) {
	const applicable = document => {
		const relative = path.relative(root, document.uri.fsPath).split(path.sep).join("/");
		return document.uri.scheme === "file" && relative !== ".." && !relative.startsWith("../") && !path.isAbsolute(relative) && !/^rules\/.*\/tests\//.test(relative) ? relative : undefined;
	};
	const extraction = (document, range) => {
		const relative = applicable(document);
		if (!relative || !relative.endsWith(".luau")) return undefined;
		const loader = (workflow.checks.jsonExtractionLoaders || []).find(item => path.posix.matchesGlob(relative, item.path));
		if (!loader || loader.runtime !== "lute" || loader.returnContract !== "json-object" ||
			typeof loader.expression !== "string" || loader.expression.split("{file}").length !== 2) return undefined;
		const text = document.getText();
		const before = text.slice(0, document.offsetAt(range.start));
		const after = text.slice(document.offsetAt(range.end));
		if (!/^(?:(?:[ \t]*--[^\r\n]*\r?\n)|\s)*return\s+$/.test(before) || after.trim()) return undefined;
		const object = jsonObject(document.getText(range));
		if (!object) return undefined;
		const destination = document.uri.fsPath.replace(/\.luau$/, ".json");
		try {
			if (path.relative(fs.realpathSync(root), fs.realpathSync(document.uri.fsPath)).split(path.sep).join("/") !== relative) return undefined;
			if (fs.existsSync(destination)) return undefined;
		} catch { return undefined; }
		return {
			destination, json: JSON.stringify(object, null, 2) + "\n",
			replacement: loader.expression.replace("{file}", () => JSON.stringify(path.basename(destination))),
		};
	};
	const provider = {
		provideCodeActions(document, _range, context) {
			const relative = applicable(document);
			if (!relative) return [];
			const actions = [];
			for (const diagnostic of context.diagnostics) {
				const code = typeof diagnostic.code === "object" ? diagnostic.code.value : diagnostic.code;
				const start = diagnostic.range.start;
				const source = actionSources.get(document.uri.toString() + ":" + code + ":" + start.line + ":" + start.character);
				if (source === undefined || document.getText() !== source) continue;
				if (code === "path-headers") {
					const repair = headerEdit(source, relative);
					if (!repair) continue;
					const action = new vscode.CodeAction("Fix path header", vscode.CodeActionKind.QuickFix);
					action.diagnostics = [diagnostic];
					action.command = { command: command("fixHeader"), title: action.title, arguments: [document.uri, document.version, source] };
					actions.push(action);
				} else if (code === "declarative-data" && extraction(document, diagnostic.range)) {
					const action = new vscode.CodeAction("Extract static table to JSON…", vscode.CodeActionKind.RefactorExtract);
					action.diagnostics = [diagnostic];
					action.command = { command: command("extractJson"), title: action.title, arguments: [document.uri, document.version, source, diagnostic.range] };
					actions.push(action);
				}
			}
			return actions;
		},
	};
	const current = async (uri, version, source) => {
		const document = await vscode.workspace.openTextDocument(uri);
		return document.version === version && document.getText() === source && applicable(document) ? document : undefined;
	};
	return [
		vscode.languages.registerCodeActionsProvider({ scheme: "file", language: "luau" }, provider),
		vscode.commands.registerCommand(command("fixHeader"), async (uri, version, source) => {
			const document = await current(uri, version, source);
			const repair = document && headerEdit(source, applicable(document));
			if (!repair) return;
			const edit = new vscode.WorkspaceEdit();
			edit.replace(uri, new vscode.Range(0, 0, 0, repair.length), repair.text);
			await vscode.workspace.applyEdit(edit);
		}),
		vscode.commands.registerCommand(command("extractJson"), async (uri, version, source, range) => {
			const document = await current(uri, version, source);
			const preview = document && extraction(document, range);
			if (!preview) return;
			const choice = await vscode.window.showInformationMessage("Extract static table to JSON?", {
				modal: true,
				detail: path.basename(preview.destination) + "\n" + preview.json + "\nLuau replacement:\n" + preview.replacement,
			}, "Extract");
			if (choice !== "Extract") return;
			const fresh = await current(uri, version, source);
			const confirmed = fresh && extraction(fresh, range);
			if (!confirmed || JSON.stringify(confirmed) !== JSON.stringify(preview)) return;
			const destination = vscode.Uri.file(confirmed.destination);
			const edit = new vscode.WorkspaceEdit();
			edit.createFile(destination, { overwrite: false, ignoreIfExists: false });
			edit.insert(destination, new vscode.Position(0, 0), confirmed.json);
			edit.replace(uri, range, confirmed.replacement);
			await vscode.workspace.applyEdit(edit);
		}),
	];
}

module.exports = { registerRuleActions, headerEdit, jsonObject };
