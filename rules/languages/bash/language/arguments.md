# Bash expansions and command arguments

Treat each command argument as a distinct value. Quote scalar expansions (`"$path"`, `"$value"`), use `"$@"` to forward positional arguments, and use `"${options[@]}"` to expand an argument array without splitting its elements.

Place a command's reusable options in a clearly named array. Prefer one flag, or one flag-value pair, per line so each setting can be read and changed independently. For tunable fields, add a short inline comment saying what the value controls and exactly what can be changed.

```bash
# List the runner's reusable settings as separate arguments to preserve their values.
act_options=(
    --pull=false                              # Change to true to pull runner container images.
    --action-offline-mode                     # Remove to allow cached actions to be refreshed.
    --bind                                    # Remove to copy the workspace instead of bind-mounting it.
    --concurrent-jobs 1                       # Increase 1 to allow more concurrent jobs.
    --artifact-server-path "$artifact_store"  # DO NOT CHANGE HERE; change artifact_store above.
    --secret GITHUB_TOKEN=                    # Leave empty for this local run; never commit a real token.
)

# Add the workflow-specific input when invoking the runner.
act push "${act_options[@]}" --workflows "$ci_workflow"
```

Keep the CLI's actual syntax: do not replace `--flag=value` with `--flag value` or vice versa unless that command supports it. Separate common options from invocation-specific options, and use descriptive names when two commands need different settings.

Do not build commands as space-separated strings or execute assembled commands with `eval`. Quote command substitutions such as `"$(...)"` when their result is one value. Use `[[ ... ]]` for Bash tests, `(( ... ))` for arithmetic, and `--` when a utility supports it and a value might begin with a hyphen.

Expansion is not a universal quoting exercise. Intentional globbing or word splitting must be visible and justified, not silently introduced by an unquoted variable. Keep paths with spaces intact. Do not concatenate user-supplied data into shell source.
