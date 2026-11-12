# CI implementation

`.github/workflows/ci.yml` runs Build, Tests, the required `validate` check, and isolated publication jobs on trusted source events. `.github/workflows/code-review.yml` independently runs read-only, headless source review on pull requests and manual dispatches. Legacy generated workflow execution remains available in the underlying Luau modules only.

Edit CI behavior and component implementations under `ci/`. Edit publication switches in `.github/config/targets.toml`. Scheduler policy, reports, and the credential catalog live under `.github/config/`. GitHub API integrations are grouped under `ci/github/`. Native GitHub job adapters are keyed by component identity under `.github/config/jobs/`. Draft adapters are kept under `jobs/drafts/`.

Validation uses the `validate` profile. Source Build prepares products; Publish owns every external mutation under existing credential/environment gates. Readiness uses the read-only `remote-read` profile on source. Preflight resolves the same discovered graph without hosted credentials. Fork/PR Validation remains an inline read-only graph, since creating an execution branch would require publication authority. Hosted Bootstrap stops after successful dispatch; Pipeline owns the eventual execution result. Failed delegation never falls back to privileged inline execution.

The commented `credentials.json` catalog defines runtime sources, verifiers, roles, and profiles. GitHub Actions discovers GitHub PATs by token format without a naming convention. Classic scopes are inspected once per job. A read-only repository probe can establish visibility. GitHub still decides whether the actual write is allowed. Existing named bindings remain available for explicitly configured credentials and migration fallbacks.

The source ruleset requires the `validate` job from **CI**.

### Credential providers

Set `profiles.source-ci.sources` to the ordered source IDs to use. Select at most one hosted transport. The default GitHub-context source passes the context only to the source gate and credential-selection steps that need it. The selector forwards only the selected values to component processes. A project can opt into listed discovery with `discovery: "listed"` and a `secrets` array of GitHub key names.

To use a broker, configure an `oidc` source with its HTTPS `endpoint` and `audience`, then reference it from the profile. The broker receives a GitHub identity token in the Authorization header and a JSON body with `profile`, `roles`, and `requests`. Each request carries the role, service, operation, target, target list, and requirements. Return named credentials as strings in `credentials`. For capability credentials, return `{ "value": "...", "grants": { "operation": "...", "targets": ["..."], "repository": {}, "organization": {}, "classic": [] } }` keyed by role. A legacy string response can still qualify through the verifier. Configure broker policy to validate signed GitHub claims and authorize each requested operation and target independently. Bootstrap runs on protected source and generated jobs run on temporary CI branches.

Command sources and verifiers receive JSON on stdin and return JSON on stdout. A source receives `{profile, requests}` and returns an array of candidates with `value`, optional `role`, and optional provider metadata. A verifier receives `{request, candidate}` and returns `{state, missing?, extraPermissions?, kind?, targetAccess?}`. Custom verifier roles declare `candidateSources` to opt into specific sources. Adapters run without the ambient workflow credential context. Keep all values and provider responses out of logs.


## VS Code setup

Install the recommended [Workbench Bridge](https://marketplace.visualstudio.com/items?itemName=Kooraseru.workbench-bridge) extension when working in VS Code. The trusted workspace command starts `dependencies/packages/editor/editorIntegration/client.cjs`, which runs dependency setup and native preflight checks through the bridge. Setup progress, failures, checker findings, and reruns appear in the workspace status bar, output channel, and Problems panel. The same loader and checker remain available directly from the command line.

## Local CI and GitHub stages

Run the complete contributor validation path with one command from the repository root:

```sh
bash ci/run.sh
```

The launcher uses the existing dependency installer, runs all eligible read-only Build components through the Luau planner, then runs the repository's Node test suites. It does not require GitHub credentials or run publication components. GitHub runs the same Luau Build entry and the same `ci/test.sh` test entry as separate jobs.

`.github/workflows/ci.yml` now owns Build, Test, the required `validate` check, and Publish stages. Publication is available only on trusted `source` pushes or an explicitly publishing manual dispatch. Components are executed by Luau within each stage; they are not rendered as temporary branch workflows. Verified component archives and manifests are transferred between jobs. GitHub-specific credential environments remain isolated in separate publication jobs.

The previous generated Pipeline implementation remains temporarily in the repository for compatibility and regression tests, but is not used by the authored GitHub workflow. GitHub Local Actions runs fixed CI directly through `act`; its isolated checkout adapts unsupported environment and artifact-action syntax without changing the hosted workflow. Do not assume that legacy `act` paths reproduce the staged workflow. The old source/delegation documentation below refers to the retained legacy entry point.

## Dependencies and local checks

`dependencies/dependencies.json` declares dependency sources and output locations; `dependencies/dependencies.lock` pins upstream versions, release assets, and the npm tree. Checked-in local tools live under `dependencies/packages/`, including `dependencyLoader`, `dataFormats`, and `ruleLinter`.

Install or refresh all declared dependencies and generate the local config discovery bridges with:

```sh
node dependencies/packages/core/dependencyLoader/index.ts
```

After changing dependency versions or sources in the manifest, refresh the lock and run setup again:

```sh
node dependencies/packages/core/dependencyLoader/index.ts --update-lock
node dependencies/packages/core/dependencyLoader/index.ts
```

Run a command through the loader so its dependencies are available first:

```sh
node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute --version
node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute check ci/entry.luau
node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute lint ci
```

The loader writes managed package/runtime files to `dependencies/managed/packages/`, executables to `dependencies/managed/bin/`, and generated type definitions to `dependencies/managed/types/`. These managed installations are ignored and survive deletion of `build/`. The npm provider writes its manifest, native lock, and install to dependencies/managed/npm/. See the [dependency provider contract](../dependencies/README.md). Local source packages stay checked in under `dependencies/packages/`.

## Configuration

Edit the canonical Luau config at `.vscode/config/luau/.luaurc` and the canonical TypeScript config at `.vscode/config/typescript/tsconfig.json`. Dependency setup generates root `.luaurc` and `tsconfig.json` discovery bridges for command line tools and editors. Those root bridges are ignored and hidden from Explorer; change the canonical configs instead. TypeScript includes `.ts`, `.tsx`, `.mts`, and `.cts` files across the repository, with generated output and external packages excluded. Luau strict checking is enabled in the canonical config, and TypeScript strict checking is enabled in its canonical `tsconfig.json`.

## Workflow Preflight

From the repository root, install the managed tools and the pinned Preflight package:

```powershell
node dependencies/packages/core/dependencyLoader/index.ts
```

Analyze the actual Bootstrap graph for an event:

```powershell
node dependencies/managed/npm/node_modules/preflight/bin/preflight.js plan --provider dependencies/packages/checks/preflightChecker/bootstrap/provider.cjs --entry pull_request
```

For a release plan, use `--entry push --target distribution/releases/publish`. Preflight includes the selected task's upstream dependencies. Plan analysis resolves the graph without running its tasks.

To show the pull-request plan in VS Code, add this command to the workspace's `workbenchBridge.workspaceCommands` after installing the package:

```json
["node", "dependencies/managed/npm/node_modules/preflight/bin/preflight.js", "workspace", "--provider", "dependencies/packages/checks/preflightChecker/bootstrap/provider.cjs", "--bridge-client", "dependencies/packages/editor/workbenchBridgeClient"]
```

Template owns editor workflow settings in `.vscode/config/workflow.json`. Each command is an argument array with an executable followed by its arguments. The same file controls status labels, the dependency progress notification, and which paths trigger a rerun. Reload the VS Code window after changing this configuration.

Automatic editor reruns happen after content changes are saved in watched source paths. The editor also watches on-disk changes to Luau sources and rule files, including edits made by other tools. Opening a file does not trigger either check. With rules.autoRefresh set to true in workflow.json, changes to active rules or their policy rerun Rules and rediscover validators automatically. Set it to false to get the **Refresh Rules** prompt. Reload the VS Code window after changing the setting. Rule examples are excluded. Saved fixture edits refresh fixture diagnostics separately from the workspace result. Run the fixture suites directly to verify the full acceptance matrices.

Click **Providers ready** to rerun dependency setup and reload Luau LSP. **CI Preflight** runs the compile checks and resolves the Bootstrap plans for pull requests, pushes, and manual dispatches. Plan mode does not execute the workflows. Rule violations appear in Problems.

From the workspace root, run `node dependencies/packages/editor/editorIntegration/client.cjs --problems` to read the open VS Code window’s current workspace diagnostics as JSON through Workbench Bridge. The snapshot includes diagnostics already published by Preflight, Rules, language servers, and other extensions.

The workspace host runs Luau LSP analysis at startup and after watched Luau changes on disk. Its findings appear as **Luau LSP workspace** in Problems, independently of the Preflight and Rules status labels. Analysis includes rule fixtures. Even fixtures expected to trigger a repository rule must pass Luau type checking. The host uses the configured executable, the installed extension's binary, or a command on PATH.

Workspace analysis invokes the same Luau LSP executable as the extension with its effective analyzer settings and base Luau configuration. When native Luau diagnostics arrive, they take precedence over matching workspace analysis and Lute findings at the same location. The workspace finding returns if the native diagnostic is withdrawn.

Rule diagnostics carry full spans and link to the owning rule. Expected fixture findings use the **Rule fixture** source in Problems and default to warning. They do not count against either status. Rules reports lint violations and fixture regressions. Preflight reports TypeScript and Luau compile-check results. Saving a fixture refreshes rule results.

JSON extraction is opt-in. In workflow.json, set checks.jsonExtractionLoaders to an array of objects with path (workspace glob), runtime ("lute"), returnContract ("json-object"), and expression (a project-owned Luau expression with one {file} placeholder). Preflight replaces the placeholder with the quoted sibling filename. The expression must load relative to the module and return the same validated shape. The default has no extraction loaders.

### Rules severity

See the [Rules settings contract](../rules/general/workflows/review/checker-contract.md) for discovered IDs, rule settings, and severity overrides. Run the dependency loader with --update-lock after changing a dependency declaration.

## Local GitHub Actions

From the repository root, run `node dependencies/packages/ci/localActions/run.cjs` or use the **Run GitHub Actions locally** VS Code task.


## Local execution

Run normal dependency setup, then use the **CI: Run locally** task or GitHub Local Actions workflow button. The extension's supported `actCommand` setting routes through the same repository launcher. `act` must be on PATH. Informational flags (`--help`, `--version`, `--list`) pass through without starting a pipeline.

```sh
node dependencies/packages/core/dependencyLoader/index.ts
node dependencies/packages/ci/localActions/run.cjs
node dependencies/packages/ci/localActions/run.cjs --input operation=build
node dependencies/packages/ci/localActions/run.cjs --input operation=readiness
```

Local `act` stages default to a 30-minute timeout, adjustable with `CI_LOCAL_TIMEOUT_MINUTES` (1–240). The launcher allocates a run-specific artifact server path and port, so do not pin either in `.actrc`. Failed runs preserve their stage logs under `build/run/<id>/` and invocation records in `.workspace/ci/runs/`.

On hosted GitHub Actions, manual dispatch defaults to `publish=false`: Build, Tests, and Validation run without external publication. Publication can be explicitly requested on a trusted source dispatch; source pushes retain the existing publication policy after a successful `validate` gate. Pull requests cannot publish. Fixed-stage publication requires `CI_STAGE_MODE=fixed` and validates the exact source ref and event; legacy generated-branch execution retains its existing checks.

The sample release and package conflict policies default to `skip`, not `replace`. To replace a tag, release, or package version, opt in explicitly after reviewing the generated outputs. Publication rehearsals route both GitHub API requests and release-asset uploads to the local test server. Pages and attestation components currently prepare inputs only; the fixed hosted CI workflow does not yet deploy Pages or sign attestations.

The default is `workflow_dispatch` with `operation=validation`. Explicit events, `--input operation=...`, dotenv input files, and event payloads are honored. Local Build automatically runs the generated controller and reusable Build workflow in an isolated checkout, then exports verified ordinary files. Publish is omitted locally. The launcher suppresses ambient GitHub-token discovery and default secret-file loading for local execution. Readiness needs explicit read authorization; no publication is performed as verification.

Current compiled outputs live under `build/artifacts/`; generated products stay under `build/github/`. Each invocation retains its own `build/run/<id>/outputs/` snapshot, Start and execution logs, stage reports, generated workflows, and internal transport archives. The previous successful current outputs remain intact after a failed run or export. Unowned or user-modified files cause an ownership conflict instead of being overwritten. The output manifest records paths, sizes, hashes, source revision, and the tracked working-copy digest.

Current-output ownership and v2 pipeline records live under ignored `.workspace/ci/`. Old v1 invocation records remain readable. Do not delete `.workspace/` as build cleanup. Archives are transport state; consumers inspect or launch the exported files directly.

## Headless code review

Pull requests into `source` run `.github/workflows/code-review.yml` without opening an editor or exposing repository secrets. The workflow installs the project's managed checker dependencies and runs both Preflight (`--ci`) and repository Rules (`--rules`) through their existing CLIs. TypeScript, Lute, Bootstrap plan, and configured rule findings appear in GitHub job annotations and a summary. This does not include VS Code-only or extension-provided diagnostics unless a separate headless analyzer is configured.

The workflow uploads every diagnostic as `code-review-findings/diagnostics.json` plus `summary.md`. To avoid flooding review pages with existing warnings, only the first 50 findings affecting PR-changed files are annotated; the full report retains the rest. Errors in changed files or checker failures fail Code Review; existing errors in unrelated files are reported without blocking an unrelated pull request. Expected invalid rule fixtures are omitted from the counted diagnostics, while unexpected fixture outcomes remain errors. A manual workflow dispatch reviews the whole repository.

To run the same checks without GitHub or an editor, run `node dependencies/packages/core/dependencyLoader/index.ts` followed by `node ci/code-review.cjs`. The full report is written to `build/code-review/`.
