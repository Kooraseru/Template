#!/usr/bin/env bash

set -euo pipefail

# Select a workflow-owned log and forward the remaining CI entry arguments.
workflow_name="${1:?Expected a workflow name}"
log_name="${2:?Expected a log name}"
shift 2

case "$workflow_name" in
	start|validation|readiness|build|publish) ;;
	*)
		printf 'Unsupported workflow log: %s\n' "$workflow_name" >&2
		exit 2
		;;
esac

if [[ ! $log_name =~ ^[a-zA-Z0-9_-]+$ ]]; then
	printf 'Invalid workflow log name: %s\n' "$log_name" >&2
	exit 2
fi

# Stream the component output to its log and preserve the CI process status.
run_id="${CI_LOCAL_RUN_ID:-${CI_RUN_ID:-${GITHUB_RUN_ID:-cli}-${GITHUB_RUN_ATTEMPT:-1}}}"
if [[ ! $run_id =~ ^[a-zA-Z0-9_-]+$ ]]; then exit 2; fi
export CI_RUN_ID="$run_id" CI_PHASE="$workflow_name"
log_directory="build/run/$run_id/$workflow_name/logs"
mkdir -p "$log_directory"
dependencies=()
if [[ ${1:-} == --report ]]; then
	dependencies=(--only workspace.npm)
fi
node dependencies/packages/core/dependencyLoader/index.ts "${dependencies[@]}" --exec luau.lute run ci/entry.luau "$@" 2>&1 | tee "$log_directory/$log_name.log"
