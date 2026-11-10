# Workspace runtime / MCP verification

Base inspected before implementation: `source` at `51e3799793383dc7cc33c481a9fe59a5457bc043` (also `origin/source` when fetched). Working tree was clean. Environment: Windows, native Node 24.14.0 ARM64; configured Lute Windows x64 compatibility binary reports 1.0.1.

## Recorded baseline

- Existing MCP exposed `editor_get_problems` and `rules_list`; initialization and both tools passed existing tests. Loader/MCP suites: 13/13 passed before implementation.
- TypeScript, Lute and bootstrap plans for `pull_request`, `push`, and `workflow_dispatch` completed without findings before changes.
- Installed runtime, npm tree, generated types and loader state were under `build/dependencies/`; the saved editor selection used `build/run/editor-problems/`. No legacy editor selection directory was present on this machine.
- Original and migrated local Actions launchers were exercised with `--list`. Both fail on the same existing `ci.yml` schema error: `environment.deployment` is an unknown property, followed by job-shape errors near lines 36–46. The original launcher was loaded from `source` for comparison; the only workflow edits are dependency executable paths. This blocks discovery/execution before component runs. Neither CI Check nor CI Publish is claimed to pass. No unrelated CI rewrite was attempted.

## Verified after migration

- All 58 discovered Node tests under `dependencies/packages/` pass, including existing editor/rule policy/bootstrap tests and new focused coverage.
- Normal setup migrates the existing installation and succeeds. A second incremental reload leaves installation-state contents and modification time unchanged. Executing Lute through the loader succeeds.
- Provider tests install staged dependencies, exercise incremental invalidation, stale locks, failed resolve/install preservation, output conflicts and interrupted publication recovery. Legacy `root: "build"` exports are accepted and normalized to `managed`.
- Migration tests preserve original installed files and editor selection, avoid overwriting newer selections, and verify that deleting an isolated fixture's `build/` leaves dependencies and workspace state intact. The user's build tree was not deleted.
- TypeScript compilation checks, Lute checks and all three bootstrap plans pass with the new paths. Managed/workspace trees are excluded from source checks; editor tests verify managed changes do not trigger compilation/rule refresh.
- MCP initialization, six-tool discovery, invocation, structured status, authorization rejection, resource reads and subscribe/unsubscribe pass for protocol versions `2025-11-25` and `2026-07-28`.
- Subscription tests cover opt-in delivery, change-only invalidations, unsubscribe and connection-close cleanup.
- Live Workbench Bridge connection, diagnostic counts and a paginated VS Code document read succeeded without focusing or launching a window. The generic bridge implementation/client is unchanged.
- Adapter tests cover unsaved text, UTF-16 pagination, dirty/version metadata, authorized buffer edits without saving, stale versions, untrusted workspaces, missing authorization, invalid/overlapping ranges, rejected edits, Windows escapes, and junctions outside the workspace or into private state.
- Mocked connection tests cover absent/ambiguous sessions and ensure denied writes never connect. CI tests distinguish missing, failed and corrupt execution data.
- Changed-file editor diagnostics contained no errors. The changed Luau workflow generator has existing function-documentation warnings on unchanged declarations; no new warning was identified at the changed executable path.

## Limits and remaining verification

- Local CI execution remains blocked by the baseline `act` schema failure. Hosted workflows and publication were not run as validation of this branch.
- Full host/container artifact compilation and a fresh network download of every dependency were not performed. Existing dependencies were migrated; provider installation was tested in isolated fixtures.
- Live editor mutations were not performed on the user's active workspace. Permission/edit behavior uses a VS Code API fixture; native undo and editor races still benefit from an isolated Extension Development Host test.
- Physical multiple-window discovery and other platform desktop sessions were not created; disconnected/ambiguous behavior uses injected bridge connections.
- Client-specific Codex/Gemini/Antigravity subscription rendering is unverified. Polling remains available and correctness never depends on notifications.
- Dependency readiness is an installed-state/output-existence observation, not proof of lock freshness or successful compilation. Run the loader/checks for that proof.
- CI status exposes recorded local `act` invocation outcomes, exit codes and failure summaries. Per-workflow/component state and arbitrary extension history are unavailable; terminal/build logs supply detailed output. Interrupted records become unknown when their recorder process no longer exists.
- Legacy dependency/session copies remain for recovery. Setup does not clean `.workspace/`; no user state is deleted.
