#!/usr/bin/env bash
# rule-runner=bash
set -euo pipefail

syntax_shell=${PREFLIGHT_BASH:-bash}
mode=${1:---check}
root=${2:-.}
fixture_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/tests" && pwd -P)"

check_file() {
	local file=$1
	local output
	if output=$("$syntax_shell" -n "$file" 2>&1); then
		return 0
	fi
	local line
	line=$(printf '%s\n' "$output" | sed -nE 's/.*line ([0-9]+).*/\1/p' | head -n 1)
	line=${line:-1}
	local message
	message=$(printf '%s' "$output" | tr '\r\n' ' ' | sed -E 's/[[:space:]]+/ /g')
	printf '%s:%s:1: error: Bash syntax check failed: %s\n' "$file" "$line" "$message"
	return 1
}

if [[ $mode == --test ]]; then
	check_file "$fixture_dir/syntax-valid.sh"
	if check_file "$fixture_dir/syntax-invalid.sh"; then
		printf 'invalid Bash fixture was accepted\n' >&2
		exit 1
	fi
	exit 0
fi

while IFS= read -r -d '' file; do
	check_file "$file" || true
done < <(find "$root" \( -type d \( -name .git -o -name build -o -name node_modules \) -prune \) -o \( -type f -name '*.sh' -print0 \))
