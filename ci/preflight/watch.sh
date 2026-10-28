#!/usr/bin/env bash

set -uo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

if [[ -n ${USERPROFILE:-} ]]; then
	HOME=$USERPROFILE
	export HOME
fi

# Preserve paths supplied by the VS Code extension across nested MSYS2 Bash processes.
export PREFLIGHT_LUAU_LSP PREFLIGHT_STYLUA_PATH PREFLIGHT_VSCODE_GLOBAL_STORAGE

run_preflight() {
	local output
	local status
	output="$(CI_EVENT=workflow_dispatch; export CI_EVENT; source ci/toolchain/lune.sh run ci/entry.luau --preflight-only 2>&1)"
	status=$?

	if ((status == 0)); then
		if [[ -n $output ]]; then
			printf '%s\n' "$output"
		fi
		return 0
	fi

	local diagnostic_count
	diagnostic_count="$(printf '%s\n' "$output" | grep -Ec '^::diagnostic::|^[^:]+:[0-9]+:[0-9]+:[0-9]+: (error|warning|info): ' || true)"
	if ((diagnostic_count > 0)); then
		printf '%s\n' "$output" | grep -E '^::diagnostic::|^[^:]+:[0-9]+:[0-9]+:[0-9]+: (error|warning|info): '
		return "$status"
	fi

	local runtime_version
	runtime_version="$(bash ci/toolchain/lune.sh --version 2>/dev/null | head -n 1)"
	local syntax_location
	syntax_location="$(printf '%s\n' "$output" | sed -nE 's#^syntax error: .*\\template\\([^:]+):([0-9]+):.*#\1 \2#p' | head -n 1)"
	if [[ -n $syntax_location ]]; then
		local source_path line_number
		read -r source_path line_number <<<"$syntax_location"
		source_path="${source_path//\\//}"
		printf '%s.luau:%s:1:2: error: Preflight could not parse this file with %s. Use the repository-pinned Lune 0.11.1 runtime.\n' \
			"$source_path" "$line_number" "$runtime_version"
	else
		local first_error
		first_error="$(printf '%s\n' "$output" | grep -m 1 -E '^(syntax error:|::error::|Error:|error:)' || true)"
		first_error="${first_error:-Preflight exited before producing diagnostics}"
		printf 'ci/entry.luau:1:1:2: error: Preflight failed with %s: %s\n' "$runtime_version" "$first_error"
	fi
	return "$status"
}

if [[ ${1:-} == "--once" ]]; then
	run_preflight
	exit $?
fi

snapshot() {
	find . \( -path './.git' -o -path './build' \) -prune -o -type f -print0 \
		| sort -z \
		| xargs -0 sha256sum \
		| sha256sum
}

previous=""
while true; do
	runtime_path="$(bash ci/toolchain/lune.sh --print-path 2>/dev/null || true)"
	current="$(snapshot):$runtime_path"
	if [[ $current != "$previous" ]]; then
		printf '%s\n' '::preflight-start::'
		run_preflight || true
		printf '%s\n' '::preflight-end::'
		previous="$current"
	fi
	sleep 1
done
