# workspace MCP tooling

status: initial implementation. The existing `.codex/` hooks remain active until lifecycle parity can be verified.

## goal

Provide agent-neutral, workspace-owned MCP capabilities for editor diagnostics and Luau rule discovery without modifying Workbench Bridge. After the lifecycle migration, repository-local `.codex/` hooks should no longer be necessary.

## architecture

- The MCP server lives in `dependencies/packages/editor/mcpServer/`, using the existing Workbench Bridge client and private workspace-session discovery.
- Reuse `editorIntegration/problems.cjs` as the authoritative VS Code diagnostics source.
- Keep tools explicit, read-only by default, and scoped to the selected workspace. Do not expose arbitrary `vscode` property access, remote calls, or shell execution to MCP clients.
- Register Codex, Antigravity, and other clients through their supported user-level or workspace configuration. The MCP interface must not depend on any one agent.
- Keep Workbench Bridge's public protocol and extension implementation unchanged.

## available tools

| capability | behavior |
| --- | --- |
| `editor_get_problems` | Return current workspace-scoped VS Code diagnostics, including paths, ranges, severity, source, and code. Optional `file`, `severity`, and `limit` filters; response includes counts and a truncation flag. A disconnected editor produces a tool error. |
| `rules_list` | Discover Luau validator directories and count `.luau` fixtures under `valid`, `invalid`, and `review`. Optional `id` filter accepts an exact rule ID or unambiguous name. An inventory is not a validation result. |

The server also supplies instructions through MCP initialization so clients can discover the intended workflow without inspecting this repository. Both tools are read-only and return structured data plus text.

## setup

1. Run the normal workspace dependency setup to install the locked MCP SDK:

   ```sh
   node dependencies/packages/core/dependencyLoader/index.ts
   ```

2. Install and activate [Workbench Bridge](https://github.com/Kooraseru/workbench-bridge) in VS Code for live editor diagnostics. The server will discover the single running session for this workspace; when multiple sessions exist, set `WORKBENCH_BRIDGE_SESSION` to the chosen session record path. `rules_list` is available without a VS Code session.
3. Configure your local agent's stdio MCP server command with an absolute path to `dependencies/packages/editor/mcpServer/index.mjs`. The agent launches the process; Workbench Bridge is the already-running VS Code extension.

For Codex, put the following in your **user-level** `~/.codex/config.toml` (substitute your actual checkout path):

```toml
[mcp_servers.template_workspace]
command = "node"
args = ["C:/absolute/path/to/Template/dependencies/packages/editor/mcpServer/index.mjs"]
```

For Gemini CLI, put this in your **user-level** `~/.gemini/settings.json`, or merge the `mcpServers` entry into your existing settings:

```json
{
  "mcpServers": {
    "template-workspace": {
      "command": "node",
      "args": ["C:/absolute/path/to/Template/dependencies/packages/editor/mcpServer/index.mjs"]
    }
  }
}
```

Other MCP clients can use the same stdio command. Each configuration must point to the intended checkout; do not let an agent in another repository silently reuse this workspace's tools. The server uses its own checkout root and writes only protocol messages to stdout. Do not configure a shared HTTP endpoint for this initial release.

Official client references: [Codex MCP](https://developers.openai.com/codex/mcp) and [Gemini CLI MCP](https://geminicli.com/docs/tools/mcp-server/).

To run the MCP tests after dependency setup:

```sh
node --test dependencies/packages/editor/mcpServer/*.test.cjs
```

## future capability

Only after real-editor verification, consider a stateful `editor_compare_problems` operation for before-and-after diagnostics. Include stable identities, workspace/session isolation, and cleanup.

## lifecycle compatibility

MCP tool availability does not guarantee execution at session start or around file edits. Preserve existing automatic hook behavior until an explicitly selected replacement has been tested. Optional lifecycle integration belongs in agent configuration or an independently maintained adapter, not in Workbench Bridge.

The current `/rule-audit` behavior provides instructions and an inventory; it does not execute an audit. Any replacement must preserve that distinction.

## verification

- [x] MCP initialization, tool discovery, and calls work over stdio.
- [ ] Diagnostics agree with the existing `client.cjs --problems` output in a live VS Code workspace and remain restricted to the chosen workspace.
- [x] Rule discovery identifies nested rule paths and rejects ambiguous validators or identities.
- [ ] Missing, ambiguous, and disconnected Workbench Bridge sessions are verified against real editor processes without exposing discovery tokens (missing-session behavior has automated coverage).
- [ ] Existing editor integration and rule tests continue passing. An existing editor-integration assertion (`activate.test.cjs`, dirty document generation, expected 1 diagnostic set but received 2) fails in this Linux checkout; the new MCP tests pass independently.
- The final migration removes tracked `.codex/` files and updates `.gitignore` and `AGENTS.md` only after equivalent behavior is verified.
- No changes to Workbench Bridge, repository settings, or GitHub Actions workflows.
