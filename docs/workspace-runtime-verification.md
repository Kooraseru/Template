# Workspace runtime / MCP verification

Base inspected before implementation: `source` at `51e3799793383dc7cc33c481a9fe59a5457bc043` (also `origin/source` when fetched). Working tree was clean. Environment: Windows, native Node 24.14.0 ARM64; configured Lute Windows x64 compatibility binary reports 1.0.1.

## Recorded baseline

- Existing MCP exposed `editor_get_problems` and `rules_list`; initialization and both tools passed existing tests. Loader/MCP suites: 13/13 passed before implementation.
- TypeScript, Lute and bootstrap plans for `pull_request`, `push`, and `workflow_dispatch` completed without findings before changes.
- Installed runtime, npm tree, generated types and loader state were under `build/dependencies/`; the saved editor selection used `build/run/editor-problems/`. No legacy editor selection directory was present on this machine.
- Original and migrated local Actions launchers were exercised with `--list`. Both fail on the same existing `ci.yml` schema error: `environment.deployment` is an unknown property, followed by job-shape errors near lines 36–46. The original launcher was loaded from `source` for comparison; the only workflow edits are dependency executable paths. This blocks discovery/execution before component runs. Neither CI Check nor CI Publish is claimed to pass. No unrelated CI rewrite was attempted.

## Verified after migration

- All 60 discovered Node tests under `dependencies/packages/` pass, including existing editor/rule policy/bootstrap tests and new focused coverage.
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

- The original local launch failures were fixed in the Local Actions follow-up below. Hosted workflows and publication were not run as validation of this branch.
- The follow-up CI Check execution compiled host/container artifacts. A cold download of every dependency on every supported platform was not performed.
- Live editor mutations were not performed on the user's active workspace. Permission/edit behavior uses a VS Code API fixture; native undo and editor races still benefit from an isolated Extension Development Host test.
- Physical multiple-window discovery and other platform desktop sessions were not created; disconnected/ambiguous behavior uses injected bridge connections.
- Client-specific Codex/Gemini/Antigravity subscription rendering is unverified. Polling remains available and correctness never depends on notifications.
- Dependency readiness is an installed-state/output-existence observation, not proof of lock freshness or successful compilation. Run the loader/checks for that proof.
- CI status exposes recorded local `act` invocation outcomes, exit codes and failure summaries. Per-workflow/component state and arbitrary extension history are unavailable; terminal/build logs supply detailed output. Interrupted records become unknown when their recorder process no longer exists.
- Legacy dependency/session copies remain for recovery. Setup does not clean `.workspace/`; no user state is deleted.


## Local Actions follow-up

The user supplied separate CI Check and CI Publish button failures after the initial PR. CI Check defaulted to an unsupported `push` event; CI Publish was rejected by act 0.2.89's schema for `environment.deployment`. Setup now generates `.actrc` with canonical `--detect-event` options, the local PR route accepts an omitted hosted payload only under ACT, and provider selection delegates source-ref enforcement to the already-guarded entry. An integration test verifies hosted feature refs are rejected and hosted source/local ACT refs are accepted before credentials or tasks are read.

The first real CI Check execution passed its components, including source host builds, then exposed a further v7 uploader incompatibility: act's artifact server rejects the `mime_type` field. Authored workflows now retain v7 uploads on GitHub and use v4 locally, with shared artifact inputs. The named bootstrap environment is retained; omitting `deployment: false` restores default GitHub deployment-record metadata for that job.

- Both authored workflows pass act discovery and dry-run with no explicit event argument.
- Real CI Check execution succeeds through validation, local artifact upload, post-actions and completion using the cached local actions/image. Host compilation executed in Docker.
- Real CI Publish execution succeeds through provider selection, bootstrap, generated local execution-plan output, local artifact upload and completion. The configured OIDC alternative is correctly skipped for the environment provider.
- The full Node suite is now 60/60; TypeScript, Lute and the three bootstrap plans pass.
- The ignored `.actrc` was generated in the current checkout; no extension code or private extension storage was changed.


## Consolidated CI and readable-output migration (2026-11-11)

Baseline before this migration: 60/60 Node tests passed on branch `capability/workspace-runtime-mcp`, starting at commit `18813ba`.

Implemented one authored `ci.yml`, with PR/manual Validation, explicit Readiness, and source Build/Publish routing. The required `validate` status remains a separate compatibility gate and fails if Start or Validation does not succeed. Generated branches contain a controller plus the required reusable stages. Publish has a native dependency on Build, uses the same execution run's verified output manifests, and is absent from local generated workflows. Hosted PR/fork Validation retains the inline read-only graph: generating a branch would require write authority that those jobs intentionally do not receive.

Verification completed:

- All 75 discovered Node tests pass. TypeScript/Lute checks and bootstrap plans for push, pull_request and workflow_dispatch pass.
- The only authored YAML is `ci.yml`; act lists Start, Validation, Readiness, Build routing and the `validate` compatibility check. Authored action locking/coverage verification passes. A rendered hosted controller, Build and Publish set also passes official Actions lock generation and offline coverage verification without creating a remote branch.
- Default local Validation completes Start, generated Validation, reporting and output export. Explicit local Build completes Start, generated Build, reporting and export. The final Build run used a frozen tracked working-copy snapshot for both invocations.
- Final local Build record: `da5f010a-616d-4742-ba41-d7185b8b9a70`. Start, Build and export are passed; Publish is disabled. It exports 36 files from eight discovered Build components, including windows-amd.exe, windows-arm64.exe and windows-intel.exe directly under `build/artifacts/application/`. Current files match manifest hashes and a separate readable snapshot remains under the run's outputs directory. The stage Markdown report and logs are also ordinary files.
- Local execution records retain the original HEAD plus the working-copy digest; tests used saved tracked snapshots while logical commits were assembled, rather than rewriting execution history to claim a different commit.
- Focused tests cover phase validation, backwards phase dependencies, output provenance, archive traversal/special entries/Windows names, undeclared paths, tampered hashes, ownership conflicts, stale-file removal, interrupted promotion recovery, junction boundaries, safe CLI defaults/input files, and v1/v2 status compatibility.
- The live editor configuration reports `githubLocalActions.actCommand = node dependencies/packages/ci/localActions/run.cjs`. Launcher discovery/version pass-through works. No focus change, extension modification, or private extension storage access was used.
- Focused live Problems checks for changed Luau integration files returned no errors. Workbench Bridge remains unchanged.

Integration findings resolved during implementation: LF shell-script handling on Windows; act's advertised-port behavior when port 0 is supplied (the launcher selects an available concrete port); portable isolated-checkout Git metadata/origin; and checkout population for local reusable workflow jobs. Failed runs retained their records/logs and did not replace current successful outputs.

Remaining limits:

- Hosted execution/publication, environment approvals, OIDC acquisition and remote branch lifecycle have not been exercised against production. Generated structure, guards, action locks and existing read/rehearsal tests provide local coverage; no live publication or ruleset mutation was performed.
- Readiness keeps its source-ref and read-token restrictions. Live authenticated readiness was not exercised during this migration.
- The extension's configured command and CLI execution were verified without moving focus. Actual workflow-button rendering/task launch in an isolated Extension Development Host remains unverified.
- The local snapshot covers saved tracked files, including staged additions. Unsaved editor buffers and untracked files are outside the CI source snapshot; stage required new files before running local CI.
- Client-specific MCP subscription presentation and live editor undo/races retain the earlier verification limits. Status polling and recorded execution data do not depend on those clients.
