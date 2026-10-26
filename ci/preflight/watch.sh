#!/usr/bin/env bash

set -uo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

find_lune() {
	local repository_lune="$root/build/tools/lune/0.11.1/lune.exe"
	if [[ -f $repository_lune ]]; then
		printf '%s\n' "$repository_lune"
		return
	fi
	if command -v lune >/dev/null 2>&1; then
		command -v lune
		return
	fi
	if command -v where.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
		local windows_lune
		windows_lune="$(where.exe lune.exe 2>/dev/null | tr -d '\r' | head -n 1)"
		if [[ -n $windows_lune ]]; then
			wslpath -u "$windows_lune"
			return
		fi
	fi
}

lune_command="$(find_lune)"

run_preflight() {
	if [[ -z $lune_command ]]; then
		printf '%s\n' 'ci/entry.luau:1:1:2: error: Lune was not found on PATH'
		return 127
	fi
	"$lune_command" run ci/entry.luau --preflight-only
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
	current="$(snapshot)"
	if [[ $current != "$previous" ]]; then
		printf '%s\n' '::preflight-start::'
		run_preflight || true
		printf '%s\n' '::preflight-end::'
		previous="$current"
	fi
	sleep 1
done
