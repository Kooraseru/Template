#!/usr/bin/env bash

set -euo pipefail

# Resolve the workspace and the generated extension files.
project_root="$(git rev-parse --show-toplevel)"
cd "$project_root"

helper=".vscode/preflight/install-helper.js"
extension_directory=".vscode/preflight"
output_directory="$project_root/build/run/preflight-extension/artifacts"
stamp="$output_directory/preflight-extension.sha256"
vsix="$output_directory/preflight-diagnostics.vsix"
reload_marker="$output_directory/preflight-reload-required.sha256"

# Check the tools before calculating extension metadata.
printf '%s\n' 'Preflight setup: checking the workspace extension.'
if ! command -v node >/dev/null 2>&1; then
    printf '%s\n' 'Preflight setup needs Node.js to build the local VSIX.' >&2
    exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
    printf '%s\n' 'Preflight setup needs npm/npx to build the local VSIX.' >&2
    exit 1
fi

npx_path="$(realpath -- "$(command -v npx)")"
if [[ ${npx_path##*/} == "npx-cli.js" ]]; then
    npx_entrypoint="$npx_path"
else
    npx_entrypoint="$(dirname -- "$npx_path")/node_modules/npm/bin/npx-cli.js"
fi
if [[ ! -f $npx_entrypoint ]]; then
    printf 'Preflight setup cannot find npm CLI JavaScript at %s\n' "$npx_entrypoint" >&2
    exit 1
fi

if ! command -v code >/dev/null 2>&1; then
    printf '%s\n' 'Preflight setup cannot find the VS Code CLI (code). Add it to PATH, then run the Preflight installation task.' >&2
    exit 1
fi

# Compare the installed extension with the current workspace source.
extension_id="$(node "$helper" identity)"
extension_hash="$(node "$helper" source-hash "$extension_directory/package.json" "$extension_directory/extension.js")"
extension_code_hash="$(node "$helper" file-hash "$extension_directory/extension.js")"
installed="$(code --list-extensions 2>/dev/null | node "$helper" is-installed "$extension_id" || true)"
extension_version="$(node "$helper" version)"
previous_hash=""
if [[ -f $stamp ]]; then
    read -r previous_hash < "$stamp"
fi

# Resolve the extension copy reported by this VS Code CLI. A matching WSL copy
# must not hide a stale local copy, because the local window may load that one.
installed_extension_path() {
    local candidate
    local candidate_hash
    candidate="$(code --locate-extension "$extension_id" 2>/dev/null || true)"
    candidate_hash="$(node "$helper" installed-hash "$candidate")"
    if [[ $candidate_hash == "$extension_code_hash" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    return 1
}

if [[ -n $installed && $previous_hash == "$extension_hash" ]] && installed_extension_path >/dev/null; then
    if [[ -f $reload_marker ]]; then
        read -r requested_hash < "$reload_marker" || requested_hash=""
        if [[ $requested_hash != "$extension_code_hash" ]]; then
            printf '%s\n' "$extension_code_hash" > "$reload_marker"
        fi
        printf '%s\n' 'Preflight setup: extension is installed; reload is still required to activate it.'
    else
        printf '%s\n' 'Preflight setup: extension is current; no reload is needed.'
    fi
    exit 0
fi

# Package, install, and verify the extension before recording its reload marker.
printf '%s\n' 'Preflight setup: building the local VSIX.'
mkdir -p "$output_directory"
(cd "$extension_directory" && node "$npx_entrypoint" --yes @vscode/vsce package --no-dependencies --skip-license --out "$vsix")

printf '%s\n' 'Preflight setup: installing the workspace VSIX.'
code --install-extension "$vsix" --force
installed_path="$(installed_extension_path || true)"
if [[ -z $installed_path ]]; then
    printf '%s\n' 'Preflight setup error: VS Code CLI did not update the extension copy it reports. Check that this CLI belongs to the open window.' >&2
    exit 1
fi
printf '%s\n' "$extension_hash" > "$stamp"
printf '%s\n' "$extension_code_hash" > "$reload_marker"

printf '%s\n' 'Preflight setup: VSIX installed. Reload this VS Code window once to activate it.'
