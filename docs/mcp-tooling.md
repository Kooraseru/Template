# workspace MCP tooling

status: proposal only. No MCP implementation is included in this initial commit.

## goal

Provide agent-neutral, workspace-owned MCP capabilities for editor diagnostics and Luau rule discovery without modifying Workbench Bridge or requiring a repository-local `.codex/` directory after migration.

## architecture

- Implement the MCP adapter within `dependencies/packages/editor/`, using the existing Workbench Bridge client and private workspace-session discovery.
- Reuse `editorIntegration/problems.cjs` as the authoritative VS Code diagnostics source.
- Keep tools explicit, read-only by default, and scoped to the selected workspace. Do not expose arbitrary `vscode` property access, remote calls, or shell execution to MCP clients.
- Register Codex, Antigravity, and other clients through their supported user-level or workspace configuration. The MCP interface must not depend on any one agent.
- Keep Workbench Bridge's public protocol and extension implementation unchanged.

## first capabilities

| capability | behavior |
| --- | --- |
| `editor_get_problems` | Return current scoped diagnostics with accurate paths, ranges, severity, source, and code. Report stale or unavailable editor state explicitly. |
| `rules_list` | Discover Luau rule directories and fixture categories from the repository. An inventory is not a validation result. |

Only after these are verified, consider a stateful `editor_compare_problems` operation for before-and-after diagnostics. Include stable identities, workspace/session isolation, and cleanup.

## lifecycle compatibility

MCP tool availability does not guarantee execution at session start or around file edits. Preserve existing automatic hook behavior until an explicitly selected replacement has been tested. Optional lifecycle integration belongs in agent configuration or an independently maintained adapter, not in Workbench Bridge.

The current `/rule-audit` behavior provides instructions and an inventory; it does not execute an audit. Any replacement must preserve that distinction.

## verification

- MCP initialization, tool discovery, and calls work over a documented transport.
- Diagnostics agree with the existing `client.cjs --problems` output and remain restricted to the chosen workspace.
- Rule discovery identifies nested rule paths and reports invalid shapes or duplicate identities.
- Missing, ambiguous, or disconnected Workbench Bridge sessions produce actionable errors without disclosing discovery tokens.
- Existing editor integration and rule tests continue passing.
- The final migration removes tracked `.codex/` files and updates `.gitignore` and `AGENTS.md` only after equivalent behavior is verified.
- No changes to Workbench Bridge, repository settings, or GitHub Actions workflows.
