#!/usr/bin/env bash

set -euo pipefail

# Resolve the project and generated inputs independently of the caller's directory.
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)"
artifact_store="$project_root/build/run/local-actions/artifacts/act-$(date +%s)-$$"
log_directory="$project_root/build/run/local-actions/logs"
start_workflow="$project_root/.github/workflows/ci.yml"
local_start_workflow="$project_root/build/run/local-actions/artifacts/ci.yml"
execution_workflow="$project_root/build/run/ci-start/artifacts/workflow.yml"
execution_event="$project_root/build/run/ci-start/artifacts/event.json"

# Keep each runner setting separate and leave the local GitHub token empty.
act_options=(
	--pull=false                                # Set true to refresh the runner image.
	--action-offline-mode                       # Remove to refresh cached actions.
	--bind                                      # Share the workspace with local jobs.
	--concurrent-jobs 1                         # Keep bound-workspace jobs sequential.
	--platform ubuntu-latest=catthehacker/ubuntu:act-latest
	--artifact-server-path "$artifact_store"    # Change artifact_store above to relocate uploads.
	--secret GITHUB_TOKEN=                      # Keep local execution unauthenticated.
)

# Stop before creating output if the runner or its entry workflow is unavailable.
if ! command -v act >/dev/null 2>&1; then
	# MSYS2 may not inherit a Windows package manager's PATH entries.
	if [[ -n ${LOCALAPPDATA:-} ]] && command -v cygpath >/dev/null 2>&1; then
		local_app_data="$(cygpath --unix "$LOCALAPPDATA")"
		for candidate in "$local_app_data"/Microsoft/WinGet/Packages/nektos.act*/act.exe; do
			if [[ -f $candidate ]]; then
				export PATH="$(dirname -- "$candidate"):$PATH"
				break
			fi
		done
	fi
	if command -v cmd.exe >/dev/null 2>&1; then
		windows_act="$(cmd.exe /c where act 2>/dev/null | tr -d '\r' | grep -i '\\act\.exe$' | head -n 1 || true)"
		if [[ -n $windows_act ]]; then
			act_directory="$(dirname -- "$(cygpath --unix "$windows_act")")"
		export PATH="$act_directory:$PATH"
		fi
	fi
	if ! command -v act >/dev/null 2>&1; then
		printf 'Missing required command: act\n' >&2
		exit 1
	fi
fi

if [[ ! -f $start_workflow ]]; then
    printf 'Missing workflow: %s\n' "$start_workflow" >&2
    exit 1
fi

# Share one artifact store across the two local workflow runs.
mkdir -p "$log_directory" "$artifact_store"
cd "$project_root"

# The local artifact server in act supports the v4 upload protocol.
sed 's#actions/upload-artifact@v7#actions/upload-artifact@v4#g' \
	"$start_workflow" > "$local_start_workflow"

printf '%s\n' 'Running CI Start locally...'
act push "${act_options[@]}" --workflows "$local_start_workflow" 2>&1 | tee "$log_directory/ci-start.log"

# CI Start writes the execution graph and event used by the second run.
if [[ ! -f $execution_workflow || ! -f $execution_event ]]; then
    printf '%s\n' 'CI Start did not produce the local execution workflow and event.' >&2
    exit 1
fi

printf '%s\n' 'Running the generated CI Execution workflow locally...'
act push "${act_options[@]}" \
    --workflows "$execution_workflow" \
    --eventpath "$execution_event" 2>&1 | tee "$log_directory/ci-execution.log"
