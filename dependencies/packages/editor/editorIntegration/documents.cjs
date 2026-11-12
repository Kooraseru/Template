"use strict";
const fs = require("node:fs");
const path = require("node:path");

// This repository module exposes only explicit capabilities through the generic bridge.
function activate({ vscode, workspaceFolder }) {
	const root = fs.realpathSync(workspaceFolder.uri.fsPath);
	function uriFor(file) {
		if (typeof file !== "string" || !file || file.includes(":") || path.isAbsolute(file) || path.win32.isAbsolute(file)) throw new Error("INVALID_FILE: provide a workspace-relative file");
		const relative = file.replaceAll("\\", "/");
		if (relative.split("/").some(part => part === ".." || part === ".git" || part === ".workspace") || relative.startsWith("dependencies/managed/")) throw new Error("INVALID_FILE: private state and managed dependencies are excluded");
		const absolute = fs.realpathSync(path.resolve(root, relative));
		const local = path.relative(root, absolute);
		const canonical = local.split(path.sep).join("/").toLowerCase();
		if (canonical.split("/").some(part => part === ".git" || part === ".workspace") || canonical.startsWith("dependencies/managed/")) throw new Error("INVALID_FILE: private state and managed dependencies are excluded");
		if (!local || local.startsWith(".." + path.sep) || local === ".." || path.isAbsolute(local)) throw new Error("INVALID_FILE: symlink or path escapes the workspace");
		if (!fs.statSync(absolute).isFile()) throw new Error("INVALID_FILE: expected an existing file");
		return vscode.Uri.file(absolute);
	}
	function requireTrust() {
		if (!vscode.workspace.isTrusted) throw new Error("UNTRUSTED_WORKSPACE: trust the workspace in VS Code first");
	}
	return {
		async getDocument({ file, offset = 0, limit = 16000 }) {
			requireTrust();
			if (!Number.isInteger(offset) || offset < 0 || !Number.isInteger(limit) || limit < 1 || limit > 64000) throw new Error("INVALID_RANGE: offset >= 0 and limit 1..64000 are UTF-16 units");
			const document = await vscode.workspace.openTextDocument(uriFor(file));
			const text = document.getText();
			return { file, version: document.version, dirty: document.isDirty, languageId: document.languageId,
				offset, length: text.length, text: text.slice(offset, offset + limit), truncated: offset + limit < text.length };
		},
		async applyEdit({ file, version, edits, authorize }) {
			requireTrust();
			if (authorize !== true) throw new Error("WRITE_NOT_AUTHORIZED: workspace_apply_edit requires authorize=true for this exact edit");
			if (!Number.isInteger(version) || version < 1 || !Array.isArray(edits) || edits.length < 1 || edits.length > 20) throw new Error("INVALID_EDIT: require a document version and 1..20 edits");
			const document = await vscode.workspace.openTextDocument(uriFor(file));
			if (document.version !== version) throw new Error("VERSION_CONFLICT: call editor_get_document and review the latest text before retrying workspace_apply_edit");
			const text = document.getText();
			const sorted = [...edits].sort((a, b) => a.start - b.start || a.end - b.end);
			let end = -1, size = 0;
			for (const edit of sorted) {
				if (!Number.isInteger(edit.start) || !Number.isInteger(edit.end) || edit.start < 0 || edit.end < edit.start || edit.end > text.length || edit.start <= end || typeof edit.text !== "string") throw new Error("INVALID_EDIT: use nonoverlapping UTF-16 offsets within the current document; adjacent edits must be combined");
				end = edit.end; size += edit.text.length + edit.end - edit.start;
			}
			if (size > 64000) throw new Error("EDIT_TOO_LARGE: restrict changed text to 64000 UTF-16 units");
			const edit = new vscode.WorkspaceEdit();
			for (const change of sorted) edit.replace(document.uri, new vscode.Range(document.positionAt(change.start), document.positionAt(change.end)), change.text);
			// No asynchronous work between version validation and handing the text edit to VS Code.
			const applied = await vscode.workspace.applyEdit(edit);
			if (!applied) throw new Error("EDIT_REJECTED: VS Code rejected the edit; reread with editor_get_document before retrying");
			return { applied: true, file, previousVersion: version, version: document.version, dirty: document.isDirty, saved: false };
		},
	};
}
module.exports = { activate };
