#!/usr/bin/env bash

set -uo pipefail

PATH="/usr/bin:/bin:$PATH"
export PATH

root="$(git rev-parse --show-toplevel)"
cd "$root"

if [[ -n ${USERPROFILE:-} ]]; then
	HOME=$USERPROFILE
	export HOME
fi

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

set +e
preflight_output="$(CI_EVENT=workflow_dispatch bash ci/toolchain/lune.sh run ci/entry.luau --preflight-only 2>&1)"
preflight_status=$?
set -e

if ((preflight_status == 0)); then
	if [[ -n $preflight_output ]]; then
		emit_context "CI Preflight passed. Its scope is the discovered CI execution graph and component contracts. Output: $preflight_output"
	else
		emit_context "CI Preflight passed with no statically detectable blockers in the discovered execution graph."
	fi
else
	emit_context "CI Preflight found blockers or failed to run (exit $preflight_status):\n$preflight_output"
fi
