# workspace MCP tooling

Status: agent-neutral stdio MCP capabilities. No repository-local agent hooks are required.

## goal

Provide agent-neutral, workspace-owned MCP capabilities for editor diagnostics and Luau rule discovery without modifying Workbench Bridge. All clients use the same capability and authorization contract.

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
| `workspace_status` | Summarize editor connectivity, diagnostic counts, recorded installed-output existence and local CI. Missing information is explicit; this does not run checks or prove lock freshness. |
| `editor_get_document` | Read an existing VS Code document, including unsaved text, version, dirty state and language. `file` is required; `offset` and `limit` paginate UTF-16 text (default 16,000; maximum 64,000 units). |
| `ci_get_status` | Discover workflow names from their YAML declarations and read the latest recorded local `act` invocations (default 5; maximum 20). Per-workflow and private extension execution state is explicitly unavailable. |
| `workspace_apply_edit` | Apply 1-20 replacements in one existing document, guarded by version and authorization. Does not save files. |
| `rules_list` | Discover Luau validator directories and count `.luau` fixtures under `valid`, `invalid`, and `review`. Optional `id` filter accepts an exact rule ID or unambiguous name. An inventory is not a validation result. |

The server also supplies instructions through MCP initialization so clients can discover the intended workflow without inspecting this repository. Read tools return compact structured data plus text. Only `workspace_apply_edit` mutates editor buffers.

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


## Filesystem and migration

`build/` contains disposable compilation, CI products, logs and reports. Installed packages, binaries, types and loader state belong in `dependencies/managed/`. Persistent editor selections and local CI invocation records belong in `.workspace/`. The latter two locations are ignored; dependency implementations remain tracked under `dependencies/packages/`, and the manifest/lock remain authoritative in `dependencies/`.

Run normal dependency setup to migrate an existing checkout. It copies legacy dependencies under the old loader lock, publishes the new installation atomically, and retains the old tree. Interrupted copies are not treated as installed. Existing new-layout installations take precedence. The legacy editor selection is copied without overwriting an existing `.workspace/editor-problems/session-file.txt`. No migration deletes user state. After setup, deleting `build/` leaves installations and persistent state intact. Do not clean `.workspace/` as build output.

## Authorization and edits

The server is read-only by default. An operator can enable the edit capability with `WORKSPACE_MCP_ALLOW_WRITES=1` in the MCP server environment. This is an independent gate from the per-call `authorize: true`, which the client must set only after explicit user approval for those exact replacements. Tool annotations are discovery hints, not authorization enforcement.

Read `editor_get_document` first, then pass its `version`, `file`, and `edits: [{start, end, text}]` to `workspace_apply_edit`, with `authorize: true`. Offsets are zero-based UTF-16 units; `end` is exclusive. Combine adjacent edits and keep removed plus inserted text within 64,000 units. Trust, existing-file scope, real paths, ranges, overlaps, authorization and version are checked before dispatch. Private `.git/`, `.workspace/`, managed installations, and links to them or outside the workspace are excluded. No create/delete/rename, save, commands, shell, or raw bridge RPC is exposed.

Version checking and dispatch happen together in the editor host using supported `WorkspaceEdit` and `workspace.applyEdit` APIs. VS Code can still reject an edit. On `VERSION_CONFLICT` or `EDIT_REJECTED`, read the document again and review the new content before retrying. Successful edits remain dirty and participate in VS Code undo; saving is a separate user action.

## CI availability

The existing local Actions task records its invocations atomically under `.workspace/ci/runs/`, including start/end time, state, exit code and a bounded failure summary. A surviving incomplete record whose recorder process is gone is `unknown`, never a claimed running or passing workflow. The CLI terminal and existing `build/run/` logs contain component-level details. No commands, arguments, credentials or terminal dumps are stored by this recorder.

Workflow names are discovered from `.github/workflows/`; their existence does not prove execution. The interface does not access other extensions' private storage or invent task history. Old invocations do not prove the current revision passes. Existing CI execution failures are independent of status availability.

## Optional status updates

`workspace://status` is an `application/json` resource with the same data as `workspace_status`. Clients may use `resources/subscribe` and `resources/unsubscribe` for opt-in `notifications/resources/updated` invalidations. While subscribed, the server samples status every five seconds and sends an invalidation only on change; read the resource again for content. Sampling stops on unsubscribe or connection close and does not overlap. The installed SDK accepts these legacy subscription methods alongside current stdio initialization. Clients using a different notification transport or without subscription support should poll the resource/tool on demand. No notification is required for correctness.


## Consolidated CI pipelines

The single authored CI workflow selects Validation by default, or explicit Build/Readiness. Local Build runs through the generated Build workflow and exports ordinary files under `build/artifacts/` and `build/github/`, with a snapshot under `build/run/<id>/outputs/`. Local Publish is disabled.

`ci_get_status` reads both v1 invocation records and v2 pipeline records. V2 includes operation, source revision, stage outcomes, export failures, and readable manifest/artifact paths. `sourceRevisionMatchesHead` compares commit identity; `currentCheckout` compares the tracked working-copy digest and is null when unavailable. Build success with failed export is an overall failure, and disabled publication never implies publication completed. Private extension history remains unavailable. Status subscriptions continue to invalidate on changes.
