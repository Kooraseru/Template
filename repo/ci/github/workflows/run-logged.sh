#!/usr/bin/env bash

set -euo pipefail

# Select a workflow-owned log and forward the remaining CI entry arguments.
workflow_name="${1:?Expected a workflow name}"
log_name="${2:?Expected a log name}"
shift 2

case "$workflow_name" in
	ci-start|ci-execution) ;;
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
log_directory="build/run/$workflow_name/logs"
mkdir -p "$log_directory"
bash dependencies/lune/bootstrap.sh run repo/ci/entry.luau "$@" 2>&1 | tee "$log_directory/$log_name.log"
