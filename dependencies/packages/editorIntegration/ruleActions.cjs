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
				if (code !== "path-headers" && code !== "declarative-data") continue;
				const kind = code === "path-headers" ? vscode.CodeActionKind.QuickFix : vscode.CodeActionKind.RefactorExtract;
				if (context.only && !context.only.contains(kind)) continue;
				if (token?.isCancellationRequested || document.getText() !== snapshot.source) continue;
				if (!range.intersection(diagnostic.range)) continue;
				const version = document.version;
				const repair = code === "path-headers" ? headerEdit(snapshot.source, relative) : undefined;
				const proposal = code === "declarative-data" ? extraction(document, diagnostic.range) : undefined;
				if (!repair && !proposal) continue;
				const edit = repair ? { start: 0, end: repair.length, text: repair.text } : {
					start: document.offsetAt(diagnostic.range.start), end: document.offsetAt(diagnostic.range.end), text: proposal.replacement,
				};
				if (!await validate(document, snapshot, key, edit).catch(() => false) ||
					token?.isCancellationRequested || document.version !== version) continue;
				const action = repair
					? new vscode.CodeAction("Fix path header", vscode.CodeActionKind.QuickFix)
					: new vscode.CodeAction("Extract static table to JSON…", vscode.CodeActionKind.RefactorExtract);
				action.diagnostics = [diagnostic];
				action.command = { command: command(repair ? "fixHeader" : "extractJson"), title: action.title,
					arguments: [document.uri, version, key, diagnostic.range] };
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

module.exports = { registerRuleActions, headerEdit, jsonObject, diagnosticKey, findingKey };
