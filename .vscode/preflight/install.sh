#!/usr/bin/env bash

set -euo pipefail

# VS Code tasks can start MSYS2 Bash without its normal login PATH setup.
if [[ -d /usr/bin ]]; then
	PATH="/usr/bin:$PATH"
	export PATH
fi

root="$(git rev-parse --show-toplevel)"
cd "$root"

extension_id="$(node -e 'const manifest = require("./.vscode/preflight/package.json"); process.stdout.write(`${manifest.publisher}.${manifest.name}`)')"
extension_hash="$(node -e '
	const fs = require("node:fs");
	const crypto = require("node:crypto");
	const hash = crypto.createHash("sha256");
	for (const file of process.argv.slice(1)) {
		hash.update(file);
		hash.update("\0");
		hash.update(fs.readFileSync(file));
	}
	process.stdout.write(hash.digest("hex"));
' .vscode/preflight/package.json .vscode/preflight/extension.js)"
extension_code_hash="$(node -e 'const fs = require("node:fs"); const crypto = require("node:crypto"); process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(".vscode/preflight/extension.js")).digest("hex"))')"
hash_installed_extension() {
	node -e '
		const fs = require("node:fs");
		const path = require("node:path");
		const crypto = require("node:crypto");
		let root = process.argv[1];
		if (process.platform === "win32" && /^\/[A-Za-z]\//.test(root)) {
			root = `${root[1]}:${root.slice(2).replaceAll("/", "\\\\")}`;
		}
		try {
			process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(path.join(root, "extension.js"))).digest("hex"));
		} catch {}
	' "$1"
}
stamp="$root/build/run/preflight-extension/artifacts/preflight-extension.sha256"
vsix="$root/build/run/preflight-extension/artifacts/preflight-diagnostics.vsix"
reload_marker="$root/build/run/preflight-extension/artifacts/preflight-reload-required.sha256"

printf '%s\n' 'Preflight setup: checking the workspace extension.'

if ! command -v node >/dev/null 2>&1; then
	printf '%s\n' 'Preflight setup needs Node.js to build the local VSIX.' >&2
	exit 1
fi
if command -v npx.cmd >/dev/null 2>&1; then
	npx_command=npx.cmd
elif command -v npx >/dev/null 2>&1; then
	npx_command=npx
else
	printf '%s\n' 'Preflight setup needs npm/npx to build the local VSIX.' >&2
	exit 1
fi

if ! command -v code >/dev/null 2>&1; then
	printf '%s\n' 'Preflight setup cannot find the VS Code CLI (code). Add it to PATH, then run “Tasks: Run Task” → “Preflight: Install workspace extension”.' >&2
	exit 1
fi

installed="$(code --list-extensions 2>/dev/null | node -e '
	const fs = require("node:fs");
	const id = process.argv[1].toLowerCase();
	const found = fs.readFileSync(0, "utf8").split(/\r?\n/).some((line) => line.trim().toLowerCase() === id);
	if (found) process.stdout.write("true");
' "$extension_id" || true)"
installed_path="$(code --locate-extension "$extension_id" 2>/dev/null | node -e 'process.stdout.write(require("node:fs").readFileSync(0, "utf8").trim())' || true)"
installed_code_hash="$(hash_installed_extension "$installed_path")"
previous_hash=""
if [[ -f $stamp ]]; then
	read -r previous_hash <"$stamp"
fi

if [[ -n $installed && $previous_hash == "$extension_hash" && $installed_code_hash == "$extension_code_hash" ]]; then
	printf '%s\n' 'Preflight setup: extension is current; no reload is needed.'
	exit 0
fi

printf '%s\n' 'Preflight setup: building the local VSIX.'
node -e 'require("node:fs").mkdirSync(require("node:path").dirname(process.argv[1]), { recursive: true })' "$vsix"
(cd .vscode/preflight && "$npx_command" --yes @vscode/vsce package --no-dependencies --skip-license --out "$vsix")

printf '%s\n' 'Preflight setup: installing the workspace VSIX.'
code --install-extension "$vsix" --force
installed_path="$(code --locate-extension "$extension_id" 2>/dev/null | node -e 'process.stdout.write(require("node:fs").readFileSync(0, "utf8").trim())' || true)"
installed_code_hash="$(hash_installed_extension "$installed_path")"
if [[ $installed_code_hash != "$extension_code_hash" ]]; then
	printf '%s\n' 'Preflight setup error: VS Code did not install the workspace extension code. Check that this VS Code CLI belongs to the open window.' >&2
	exit 1
fi
printf '%s\n' "$extension_hash" >"$stamp"
printf '%s\n' "$extension_code_hash" >"$reload_marker"

printf '%s\n' 'Preflight setup: VSIX installed. Reload this VS Code window once to activate it.'
