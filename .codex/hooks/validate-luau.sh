#!/usr/bin/env bash

set -euo pipefail

PATH="/usr/bin:/bin:$PATH"
export PATH

root="$(git rev-parse --show-toplevel)"
cd "$root"

json_escape() {
	local value=$1
	value=${value//\\/\\\\}
	value=${value//\"/\\\"}
	value=${value//$'\r'/\\r}
	value=${value//$'\n'/\\n}
	value=${value//$'\t'/\\t}
	printf '%s' "$value"
}

emit_context() {
	printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$(json_escape "$1")"
}

mapfile -d '' -t workspace_files < <(
	find . -type d \( -path './.git' -o -path './build' \) -prune -o -type f -name '*.luau' -print0
)
mapfile -d '' -t changed_files < <(
	{ git diff --name-only -z HEAD; git ls-files --others --exclude-standard -z; } | sort -zu
)

changed_luau_files=()
for file in "${changed_files[@]}"; do
	if [[ $file == *.luau ]]; then
		changed_luau_files+=("$file")
	fi
done

if ((${#changed_luau_files[@]} == 0)); then
	context="No Luau files changed. For Luau edits, review rules/languages/luau/language/types.md, rules/languages/comments.md, and rules/ci.md."
else
	context="Review changed Luau files against rules/languages/luau/language/types.md, rules/languages/comments.md, and rules/ci.md. Check class/module shape, comments, strict types, prohibited casts/any, diagnostics, and formatting. Changed files: ${changed_luau_files[*]}."
fi

profile="${USERPROFILE:-$HOME}"
if command -v cygpath >/dev/null 2>&1; then
	profile="$(cygpath -u "$profile")"
fi

analyzer="$(command -v luau-lsp 2>/dev/null || true)"
if [[ -z $analyzer && -d "$profile/.vscode/extensions" ]]; then
	analyzer="$(find "$profile/.vscode/extensions" -maxdepth 3 -type f -path '*/johnnymorganz.luau-lsp-*/bin/server.exe' -print -quit)"
fi

if [[ -z $analyzer ]]; then
	context+=$'\nLuau LSP analyzer was not found on PATH or in the VS Code extension directory.'
else
	if [[ -n ${USERPROFILE:-} ]]; then
		HOME=$USERPROFILE
		export HOME
	fi
	set +e
	analysis_output="$("$analyzer" analyze --settings config/luau/luau-lsp/settings.json --base-luaurc config/luau/.luaurc --platform standard "${workspace_files[@]}" 2>&1)"
	analysis_status=$?
	set -e
	mapfile -t diagnostics < <(printf '%s\n' "$analysis_output" | grep -E '(TypeError|SyntaxError|LintError):' | sort -u || true)
	context+=$'\nWorkspace Luau analysis scanned '"${#workspace_files[@]}"$' files and found '"${#diagnostics[@]}"$' unique diagnostics.'
	if ((${#diagnostics[@]} > 0)); then
		changed_diagnostics=()
		for diagnostic in "${diagnostics[@]}"; do
			for file in "${changed_luau_files[@]}"; do
				windows_file="$(cygpath -am "$root/$file" 2>/dev/null || printf '%s' "$file")"
				if [[ "${diagnostic,,}" == "${file,,}"* || "${diagnostic,,}" == *"/${file,,}"* || "${diagnostic,,}" == "${windows_file,,}"* ]]; then
					changed_diagnostics+=("$diagnostic")
					break
				fi
			done
		done
		if ((${#changed_diagnostics[@]} > 0)); then
			context+=$'\nDiagnostics in changed Luau files:\n'"$(printf '%s\n' "${changed_diagnostics[@]}" | sort -u)"
		fi
	fi
	if ((analysis_status != 0 && ${#diagnostics[@]} == 0)); then
		context+=$'\nLuau analyzer exited with status '"$analysis_status"' without a parsed diagnostic.'
	fi
fi

stylua="$(command -v stylua 2>/dev/null || true)"
if [[ -z $stylua ]]; then
	stylua_root="$profile/AppData/Roaming/Code/User/globalStorage/johnnymorganz.stylua"
	if [[ -d $stylua_root ]]; then
		stylua="$(find "$stylua_root" -type f -iname 'stylua.exe' -print -quit)"
	fi
fi

if ((${#changed_luau_files[@]} == 0)); then
	context+=$'\nNo changed Luau files need formatting checks.'
elif [[ -z $stylua ]]; then
	context+=$'\nStyLua CLI was not found on PATH or the VS Code extension cache; formatting check was skipped.'
else
	set +e
	format_output="$("$stylua" --check --config-path config/luau/stylua/.stylua.toml "${changed_luau_files[@]}" 2>&1)"
	format_status=$?
	set -e
	if ((format_status == 0)); then
		context+=$'\nStyLua check passed for changed Luau files.'
	else
		context+=$'\nStyLua check failed:\n'"$format_output"
	fi
fi

emit_context "$context"
