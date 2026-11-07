# Bash naming and fields

Use `snake_case` for shell-local variables, positional-argument bindings, arrays, and functions. Names should state their role: `project_root`, `artifact_store`, `act_options`, `workflow_file`, not `root`, `common`, or `args` when several such values exist.

Use `UPPER_SNAKE_CASE` for exported environment variables and external environment contracts such as `GITHUB_TOKEN` and `MSYS_NO_PATHCONV`. Do not uppercase every fixed local value just because it never changes.

Keep field declarations together when they describe one configuration boundary. Prefer separate assignments for different meanings, and leave a blank line between genuinely different groups when it helps scanning. Prefer a one-sentence comment about each field group's purpose, without decorative headings or aligned assignment columns.

```bash
# Anchor generated paths to the script location so invocation directory does not change them.
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
log_dir="$project_root/build/logs"
artifact_store="$project_root/build/artifacts/run-$(date +%s)-$$"

# Name each workflow input explicitly so callers can distinguish their roles.
ci_workflow="$project_root/.github/workflows/ci.yml"
execution_workflow="$project_root/build/workflow.yml"
execution_event="$project_root/build/event.json"
```

Use `local` for function-owned variables and `readonly` for an intentionally immutable binding when it improves the contract. Avoid `readonly` on values that legitimately change, and do not force functions around simple code merely to obtain local scope.

Arrays have plural or role-specific names such as `act_options` and `input_files`. Use an indexed array for an ordered sequence of arguments, not a scalar string pretending to be one. Bash variables are untyped strings unless explicitly declared otherwise; naming and assignment shape provide the useful distinction.

Never store credentials in checked-in defaults. An empty or redacted secret passed to a local emulator is an explicit test policy, not a general Bash convention.
