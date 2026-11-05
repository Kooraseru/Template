# Bash control flow and errors

Handle unmet preconditions before the main operation when that keeps the success path flat. Use an explicit diagnostic and a nonzero exit status when a script cannot proceed.

```bash
# Fail before execution if either the runner or its required workflow is missing.
if ! command -v act >/dev/null 2>&1; then
    printf 'Missing required command: act\n' >&2
    exit 1
fi

if [[ ! -f "$ci_workflow" ]]; then
    printf 'Missing workflow: %s\n' "$ci_workflow" >&2
    exit 1
fi
```

Use `set -euo pipefail` where a fail-fast execution contract is appropriate, but understand its limits. `errexit` is suppressed in some conditional/function contexts; it is not a replacement for deliberate handling of expected failures. With `pipefail`, a pipeline such as `command 2>&1 | tee "$log_file"` fails when an earlier command fails as well as when `tee` fails.

Use `if command; then ... else ... fi` when failure is expected or recoverable. A bare `! command` in a condition discards the original status; preserve `$?` explicitly when callers need the exact status. Guard against unset parameters under `set -u`, for example `"${1-}"` for an optional first argument.

If a script creates temporary resources, give cleanup one owner, usually a `trap` installed immediately after resource creation. Preserve useful exit statuses and do not delete durable build artifacts as though they were temporary. Avoid unnecessary subshells or process substitutions when they obscure failures.

Choose positive conditions where they actually express meaningful alternatives. The shared guard-first preference is about readable ownership of failure, not mechanical negation.
