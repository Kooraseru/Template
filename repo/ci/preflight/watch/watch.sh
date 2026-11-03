#!/usr/bin/env bash

set -uo pipefail

project_root="$(git rev-parse --show-toplevel)"
cd "$project_root"

# Preserve provider paths supplied by the VS Code extension for the Lune child process.
export PREFLIGHT_LUAU_LSP PREFLIGHT_STYLUA_PATH PREFLIGHT_VSCODE_GLOBAL_STORAGE

# Stream each diagnostic table snapshot while retaining output for startup failures.
run_preflight() {
	local output_file
	local runner_status
	local -a pipeline_status
	output_file="$(mktemp "${TMPDIR:-/tmp}/preflight.XXXXXX")" || return 1
	(
		CI_EVENT=workflow_dispatch
		export CI_EVENT
		source dependencies/lune/bootstrap.sh run repo/ci/entry.luau --preflight-only
	) 2>&1 \
		| tee "$output_file" \
		| while IFS= read -r line || [[ -n $line ]]; do
		case "$line" in
			::preflight-start::*|::diagnostics::*|::diagnostic::*)
				printf '%s\n' "$line"
				;;
		esac
	done
	pipeline_status=("${PIPESTATUS[@]}")
	runner_status="${pipeline_status[0]:-1}"
	if ((runner_status == 0)); then
		rm -f -- "$output_file"
		return 0
	fi

	# Turn failures that occur before the diagnostic engine starts into one actionable finding.
	local diagnostic_count
	diagnostic_count="$(grep -Ec '^::diagnostics::|^::diagnostic::|^[^:]+:[0-9]+:[0-9]+:[0-9]+: (error|warning|info): ' "$output_file" || true)"
	if ((diagnostic_count > 0)); then
		rm -f -- "$output_file"
		return "$runner_status"
	fi
	local output
	output="$(cat -- "$output_file")"
	rm -f -- "$output_file"

	local runtime_version
	runtime_version="$(bash dependencies/lune/bootstrap.sh --version 2>/dev/null | head -n 1)"
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
		printf 'repo/ci/entry.luau:1:1:2: error: Preflight failed with %s: %s\n' "$runtime_version" "$first_error"
	fi
	return "$runner_status"
}

if [[ ${1:-} == "--once" ]]; then
	run_preflight
	exit $?
fi

snapshot() {
	# Ignore generated output and Git metadata when detecting workspace changes.
	find . \( -path './.git' -o -path './build' \) -prune -o -type f -print0 \
		| sort -z \
		| xargs -0 sha256sum \
		| sha256sum
}

previous=""
while true; do
	runtime_path="$(bash dependencies/lune/bootstrap.sh --print-path 2>/dev/null || true)"
	current="$(snapshot):$runtime_path"
	if [[ $current != "$previous" ]]; then
		printf '%s\n' '::preflight-start::'
		run_preflight || true
		printf '%s\n' '::preflight-end::'
		previous="$current"
	fi
	sleep 1
done
