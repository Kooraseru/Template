# Bash script layout

An executable script normally begins with `#!/usr/bin/env bash`, followed by execution options if appropriate. Then arrange declarations and operations by dependency rather than by an arbitrary mandatory template.

A useful default order is:

1. shebang and execution contract
2. caller inputs and configuration fields
3. derived paths and reusable command-option arrays
4. preflight guards and helpers, when needed
5. explicit execution and output handling

The distinction between configuration and execution should be visible through names, whitespace, and command shape. Give each meaningful block a brief, preferably one-sentence comment describing what it does or why it exists. Add inline comments beside user-adjustable fields to identify the value to change and its effect. Avoid banners such as `# ===== CONFIGURATION =====`, repetitive `# Set ...` comments, or a separate comment for every field.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve paths from this script so the caller can run it from any directory.
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
artifact_store="$project_root/build/artifacts"           # Change this path to move uploaded artifacts.
log_file="$project_root/build/logs/run.log"                # Change this path to move the run log.
workflow_file="$project_root/.github/workflows/ci.yml"    # Change this path to select another workflow.

# Keep shared runner settings as distinct arguments for both readability and safe expansion.
act_options=(
    --pull=false                              # Change to true to pull runner container images.
    --concurrent-jobs 1                       # Increase 1 to allow more concurrent jobs.
    --artifact-server-path "$artifact_store"  # DO NOT CHANGE HERE; change artifact_store above.
)

# Stop before creating output when the required local runner is unavailable.
if ! command -v act >/dev/null 2>&1; then
    printf 'Missing required command: act\n' >&2
    exit 1
fi

# Prepare output directories and run from the project root expected by the workflow.
mkdir -p "$(dirname -- "$log_file")" "$artifact_store"
cd "$project_root"

# Stream output to the terminal and log while preserving a failed runner exit status.
act push "${act_options[@]}" --workflows "$workflow_file" 2>&1 | tee "$log_file"
```

Short scripts may inline the options and paths if a declaration block would add indirection without improving readability. Longer scripts can use meaningful functions, but keep the entry-point operation easy to locate. Use one-sentence phase comments to make the script's small steps navigable; keep individual statements uncommented when their role is already clear.

Executable scripts should make their working-directory expectations explicit. Prefer paths derived from `BASH_SOURCE[0]` when the caller's current directory is not part of the contract. Distinguish scripts meant to be executed from libraries meant to be sourced. Test parsing with `bash -n`, and use ShellCheck when available; these do not replace exercising platform-dependent behavior.


## Automated check

`check.luau` enforces the Bash interpreter line for every workspace shell script. Its valid and invalid samples live in `tests/` and run through the shared workspace diagnostics task. ShellCheck remains responsible for deeper shell analysis when installed.
