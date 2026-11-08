"use strict";

const crypto = require("node:crypto");
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
	const token = /\s*([A-Za-z_][A-Za-z_0-9]*|"(?:[^"\\\r\n]|\\["\\nrt])*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?|[{}\[\],;=])/y;
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
	function object(depth, root = false) {
		take("{");
		const record = Object.create(null);
		const list = [];
		let kind;
		while (next !== "}") {
			let key;
			if (next === "[") {
				advance();
				if (!next?.startsWith('"')) throw new Error("Unsupported key");
				key = JSON.parse(next);
				advance();
				take("]");
				take("=");
			} else if (next && /^[A-Za-z_][A-Za-z_0-9]*$/.test(next) && !["true", "false"].includes(next)) {
				key = next;
				advance();
				take("=");
			}
			const fieldKind = key === undefined ? "list" : "record";
			if ((kind && kind !== fieldKind) || (root && fieldKind === "list")) throw new Error("Mixed or nonobject table");
			kind = fieldKind;
			if (key === undefined) list.push(value(depth));
			else {
				if (Object.hasOwn(record, key)) throw new Error("Duplicate key");
				record[key] = value(depth);
			}
			if (next === "," || next === ";") advance();
			else if (next !== "}") throw new Error("Expected separator");
		}
		take("}");
		if (!kind) throw new Error("Ambiguous empty table");
		return kind === "list" ? list : record;
	}
	try {
		advance();
		const result = object(0, true);
		return next === undefined ? result : undefined;
	} catch { return undefined; }
}

function diagnosticKey(rule, range) {
	return JSON.stringify([rule, range.start.line, range.start.character, range.end.line, range.end.character]);
}

function findingKey(finding, source, edit) {
	const lines = source.split(/(?<=\n)/);
	const offset = (line, byte) => lines.slice(0, line - 1).join("").length +
		Buffer.from(lines[line - 1] || "").subarray(0, byte - 1).toString("utf8").length;
	const start = offset(finding.line, finding.column);
	const end = offset(finding.endLine, finding.endColumn);
	const delta = edit ? edit.text.length - (edit.end - edit.start) : 0;
	return JSON.stringify([finding.rule, finding.message,
		edit && start >= edit.end ? start + delta : start,
		edit && (end > edit.end || start >= edit.end) ? end + delta : end]);
}

function lineOffset(source, line) {
	let offset = 0;
	for (let current = 0; current < line; current++) {
		const end = source.indexOf("\n", offset);
		if (end < 0) return source.length;
		offset = end + 1;
	}
	return offset;
}

function sourceOffset(source, line, byteColumn) {
	const start = lineOffset(source, line);
	const end = source.indexOf("\n", start);
	const text = source.slice(start, end < 0 ? source.length : end);
	return start + Buffer.from(text).subarray(0, Math.max(0, byteColumn - 1)).toString("utf8").length;
}

function ruleQuickFix(snapshot, relative) {
	const { source, diagnostic } = snapshot;
	const code = path.posix.basename(snapshot.rule);
	const start = diagnostic.range.start;
	const end = diagnostic.range.end;
	const startOffset = lineOffset(source, start.line) + start.character;
	const endOffset = lineOffset(source, end.line) + end.character;
	const message = diagnostic.message.replace(/^Expected: /, "");
	const lineStart = lineOffset(source, start.line);
	const lineEndRaw = source.indexOf("\n", lineStart);
	const lineEnd = lineEndRaw < 0 ? source.length : lineEndRaw;
	const lineText = source.slice(lineStart, lineEnd).replace(/\r$/, "");
	const eol = source.includes("\r\n") ? "\r\n" : "\n";
	const edit = (title, editStart, editEnd, text) => ({ title, start: editStart, end: editEnd, text });
	const hinted = snapshot.fix;
	if (hinted && typeof hinted.title === "string" && typeof hinted.text === "string" && hinted.range) {
		const range = hinted.range;
		if ([range.line, range.column, range.endLine, range.endColumn].every(Number.isInteger) &&
			range.line >= 1 && range.column >= 1 && range.endLine >= range.line && range.endColumn >= 1) {
			const fixStart = sourceOffset(source, range.line - 1, range.column);
			const fixEnd = sourceOffset(source, range.endLine - 1, range.endColumn);
			if (fixStart <= fixEnd && fixEnd <= source.length) return edit(hinted.title, fixStart, fixEnd, hinted.text);
		}
	}

	if (code === "file-system" && message.startsWith("Declare --!strict")) {
		return edit("Add --!strict", 0, 0, "--!strict" + eol);
	}
	if (code === "file-system" && (message.startsWith("Remove the repeated section marker") || message.includes("explicitly disallowed"))) {
		if (/^\s*--#\s*[^\r\n]+\s*$/.test(lineText)) {
			const removeEnd = lineEndRaw < 0 ? lineEnd : lineEndRaw + 1;
			return edit("Remove section marker", lineStart, removeEnd, "");
		}
	}
	if (code === "blank-lines") {
		const offset = lineStart;
		if (offset > 0 && !source.slice(0, offset).endsWith(eol + eol)) {
			return edit("Insert blank line", offset, offset, eol);
		}
	}
	if (code === "indentation") {
		const prefix = source.slice(lineStart, endOffset);
		const spaces = (prefix.match(/ /g) || []).length;
		if (/^[ \t]*$/.test(prefix) && spaces > 0 && spaces % 4 === 0) {
			const replacement = "\t".repeat(spaces / 4 + (prefix.match(/\t/g) || []).length);
			return edit("Use tabs for indentation", lineStart, endOffset, replacement);
		}
	}
	if (code === "todo-comments" && message.startsWith("Describe the follow-up")) {
		if (/^\s*--+(?:\s*TODO)?[\s:!?.-]*$/.test(lineText)) {
			const removeEnd = lineEndRaw < 0 ? lineEnd : lineEndRaw + 1;
			return edit("Remove empty TODO comment", lineStart, removeEnd, "");
		}
	}
	if (code === "types" && message.startsWith("Remove the repeated Luau type assertion")) {
		return edit("Remove repeated type assertion", startOffset, endOffset, "");
	}
	if (code === "functions" && message.startsWith("A bare function declaration")) {
		const name = source.slice(startOffset, endOffset);
		const prefix = source.slice(lineStart, startOffset);
		if (/^[A-Za-z_][A-Za-z_0-9]*$/.test(name) && /\bfunction\s+$/.test(prefix)) {
			const keyword = prefix.lastIndexOf("function");
			return edit("Make helper local", lineStart + keyword, lineStart + keyword, "local ");
		}
	}
	if (code === "naming" && message.startsWith("Declare this stable Luau constant with const.")) {
		const token = source.slice(startOffset, endOffset);
		if (token === "local") return edit("Use const", startOffset, endOffset, "const");
	}
	if (code === "strings" && message.startsWith("Interpolation already converts")) {
		const expression = source.slice(startOffset, endOffset);
		const redundant = expression.match(/^tostring\s*\(\s*((?:[A-Za-z_][A-Za-z_0-9]*|true|false|nil|-?\d+(?:\.\d+)?|\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'))\s*\)$/);
		if (redundant) return edit("Remove redundant tostring", startOffset, endOffset, redundant[1]);
	}
	if (code === "strings" && message.startsWith("Use the quoted string directly")) {
		const expression = source.slice(startOffset, endOffset);
		const formatted = expression.match(/^string\.format\s*\(\s*(['"])%s\1\s*,\s*(['"])([^\\\r\n\0]*)\2\s*\)$/);
		if (formatted) return edit("Use the string literal directly", startOffset, endOffset, formatted[2] + formatted[3] + formatted[2]);
	}
	if (code === "function-documentation") {
		if (message.startsWith("Start a LuaCATS")) {
			const comment = source.slice(startOffset, endOffset);
			if (comment.startsWith("--@")) return edit("Use a LuaCATS annotation", startOffset, startOffset + 2, "---");
		}
		if (message.startsWith("Leave a blank line")) {
			return edit("Separate prose from LuaCATS tags", lineStart, lineStart, eol);
		}
		if (message.startsWith("Reserve @readonly") || message.startsWith("Remove this declaration tag")) {
			const comment = source.slice(startOffset, endOffset);
			if (comment.startsWith("---@")) {
				const removeEnd = lineEndRaw < 0 ? lineEnd : lineEndRaw + 1;
				return edit("Remove misplaced LuaCATS tag", lineStart, removeEnd, "");
			}
		}
		if (message.startsWith("Complete the LuaCATS") || message.startsWith("LuaCATS documents a parameter absent")) {
			const comment = source.slice(startOffset, endOffset);
			if (comment.startsWith("---@")) {
				const removeEnd = lineEndRaw < 0 ? lineEnd : lineEndRaw + 1;
				return edit("Remove incomplete or outdated LuaCATS tag", lineStart, removeEnd, "");
			}
		}
	}
	if (code === "path-headers") {
		const repair = headerEdit(source, relative);
		if (repair) return edit("Fix path header", 0, repair.length, repair.text);
	}
	return undefined;
}

function registerRuleActions({ vscode, root, workflow, actionSources, command, requestFile, getRevision }) {
	const previews = new Map();
	const previewScheme = command("preview").toLowerCase();
	const validate = async (document, snapshot, key, edit) => {
		const fresh = () => snapshot.revision === getRevision() && document.getText() === snapshot.source &&
			(snapshot.version === undefined || document.version === snapshot.version) &&
			actionSources.get(document.uri.toString())?.get(key) === snapshot;
		if (!fresh()) return false;
		const file = applicable(document);
		const checked = source => requestFile({ file, source, candidate: true });
		const before = await checked(snapshot.source);
		if (!fresh() || !before || before.failed || before.incomplete) return false;
		const target = before.findings.find(finding => finding.rule === snapshot.rule &&
			findingKey(finding, snapshot.source) === snapshot.target);
		if (!target) return false;
		const candidate = snapshot.source.slice(0, edit.start) + edit.text + snapshot.source.slice(edit.end);
		const after = await checked(candidate);
		if (!fresh() || !after || after.failed || after.incomplete) return false;
		const remaining = new Map();
		for (const finding of before.findings) {
			if (finding === target) continue;
			const id = findingKey(finding, snapshot.source, edit);
			remaining.set(id, (remaining.get(id) || 0) + 1);
		}
		return after.findings.every(finding => {
			const id = findingKey(finding, candidate);
			const count = remaining.get(id) || 0;
			remaining.set(id, count - 1);
			return count > 0;
		});
	};
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
		async provideCodeActions(document, range, context, token) {
			const relative = applicable(document);
			if (!relative) return [];
			const actions = [];
			const snapshots = actionSources.get(document.uri.toString());
			for (const [key, snapshot] of snapshots || []) {
				const { diagnostic } = snapshot;
				const code = diagnostic.code.value;
				const fix = ruleQuickFix(snapshot, relative);
				const proposal = code === "declarative-data" ? extraction(document, diagnostic.range) : undefined;
				if (!fix && !proposal) continue;
				const kind = proposal ? vscode.CodeActionKind.RefactorExtract : vscode.CodeActionKind.QuickFix;
				if (context.only && !context.only.contains(kind)) continue;
				if (token?.isCancellationRequested || document.getText() !== snapshot.source) continue;
				if (!range.intersection(diagnostic.range)) continue;
				const version = document.version;
				const edit = fix || {
					start: document.offsetAt(diagnostic.range.start), end: document.offsetAt(diagnostic.range.end), text: proposal.replacement,
				};
				if (!await validate(document, snapshot, key, edit).catch(() => false) ||
					token?.isCancellationRequested || document.version !== version) continue;
				const action = proposal
					? new vscode.CodeAction("Extract static table to JSON…", vscode.CodeActionKind.RefactorExtract)
					: new vscode.CodeAction(fix.title, vscode.CodeActionKind.QuickFix);
				action.isPreferred = !proposal;
				action.diagnostics = [diagnostic];
				const actionCommand = proposal ? "extractJson" : code === "path-headers" ? "fixHeader" : "applyRuleEdit";
				const args = proposal ? [document.uri, version, key, diagnostic.range]
					: code === "path-headers" ? [document.uri, version, key]
						: [document.uri, version, key, edit.start, edit.end, edit.text];
				action.command = { command: command(actionCommand), title: action.title, arguments: args };
				actions.push(action);
			}
			return actions;
		},
	};
	const current = async (uri, version, key) => {
		const document = await vscode.workspace.openTextDocument(uri);
		const snapshot = actionSources.get(uri.toString())?.get(key);
		return snapshot && document.version === version && document.getText() === snapshot.source && applicable(document)
			? { document, snapshot } : undefined;
	};
	const apply = async edit => {
		if (!await vscode.workspace.applyEdit(edit)) await vscode.window.showErrorMessage("The rule edit could not be applied.");
	};
	const previewProvider = vscode.workspace.registerTextDocumentContentProvider?.(previewScheme, {
		provideTextDocumentContent(uri) { return previews.get(uri.toString()) || ""; },
	});
	return [
		...(previewProvider ? [previewProvider] : []),
		vscode.languages.registerCodeActionsProvider({ scheme: "file", language: "luau" }, provider),
		vscode.commands.registerCommand(command("fixHeader"), async (uri, version, key) => {
			const state = await current(uri, version, key);
			const repair = state && headerEdit(state.snapshot.source, applicable(state.document));
			if (!repair || !await validate(state.document, state.snapshot, key, { start: 0, end: repair.length, text: repair.text }) ||
				state.document.version !== version) return;
			const edit = new vscode.WorkspaceEdit();
			edit.replace(uri, new vscode.Range(0, 0, 0, repair.length), repair.text);
			await apply(edit);
		}),
		vscode.commands.registerCommand(command("applyRuleEdit"), async (uri, version, key, start, end, text) => {
			const state = await current(uri, version, key);
			const relative = state && applicable(state.document);
			const fix = state && ruleQuickFix(state.snapshot, relative);
			if (!state || !fix || fix.start !== start || fix.end !== end || fix.text !== text || state.document.version !== version ||
				!await validate(state.document, state.snapshot, key, fix) || state.document.version !== version) return;
			const edit = new vscode.WorkspaceEdit();
			edit.replace(uri, new vscode.Range(state.document.positionAt(fix.start), state.document.positionAt(fix.end)), fix.text);
			await apply(edit);
		}),
		vscode.commands.registerCommand(command("extractJson"), async (uri, version, key, range) => {
			const state = await current(uri, version, key);
			const proposal = state && extraction(state.document, range);
			if (!proposal || !previewProvider) return;
			const start = state.document.offsetAt(range.start);
			const end = state.document.offsetAt(range.end);
			const previewId = crypto.randomUUID();
			const previewUri = name => vscode.Uri.from({ scheme: previewScheme, path: "/" + previewId + "/" + name });
			const luau = previewUri(path.basename(uri.fsPath));
			const json = previewUri(path.basename(proposal.destination));
			previews.set(luau.toString(), state.snapshot.source.slice(0, start) + proposal.replacement + state.snapshot.source.slice(end));
			previews.set(json.toString(), proposal.json);
			try {
				await vscode.commands.executeCommand("vscode.open", json);
				await vscode.commands.executeCommand("vscode.diff", uri, luau, "Extract static table (preview)");
				const choice = await vscode.window.showInformationMessage("Apply JSON extraction?", "Extract");
				if (choice !== "Extract") return;
				const fresh = await current(uri, version, key);
				if (!fresh || !await validate(fresh.document, fresh.snapshot, key, { start, end, text: proposal.replacement }) ||
					fresh.document.version !== version || JSON.stringify(extraction(fresh.document, range)) !== JSON.stringify(proposal)) return;
				const destination = vscode.Uri.file(proposal.destination);
				const edit = new vscode.WorkspaceEdit();
				edit.createFile(destination, { overwrite: false, ignoreIfExists: false });
				edit.insert(destination, new vscode.Position(0, 0), proposal.json);
				edit.replace(uri, range, proposal.replacement);
				await apply(edit);
			} finally {
				previews.delete(luau.toString());
				previews.delete(json.toString());
			}
		}),
	];
}

module.exports = { registerRuleActions, headerEdit, jsonObject, diagnosticKey, findingKey, ruleQuickFix, sourceOffset };
