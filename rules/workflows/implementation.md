# Implementation workflow

1. Identify the authoritative owner and contract of each behavior being changed.
2. Make the smallest cohesive change without introducing a parallel command or policy route.
3. Discover optional components from their owning directories and validate their shapes; do not update hardcoded inventories to make additions work.
4. Run relevant static checks, preflight, and supported integration or platform execution, according to the change.
5. Preserve security, provenance, and publication gates.
6. Record deferred migrations explicitly. Do not report an unfinished refactor, skipped branch, or unavailable platform as verified.

On Windows, use the configured MSYS2 Bash for repository commands and local
hooks. Examples and instructions should use Bash.

## Editor configuration changes

VS Code and language-server settings may not take effect until the user
restarts VS Code. Batch related editor configuration changes into one reviewed
edit, avoid repeated setting changes while waiting for diagnostics, and do not
claim a setting is active until the language server has reloaded.
