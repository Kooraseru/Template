# CI implementation

One permanently authored workflow, `.github/workflows/ci.yml`, acts solely as the bootstrap and required status gate. It does not enumerate component publication jobs or embed fixed credential names.

`.github/config/ci/operations.json` selects an operation for each event and declares read-only checks, generated execution policies and operation-specific branch prefixes. `.github/config/credentials.json` owns capability roles, protected-environment bindings, and secret or variable aliases. Adding an operation or component should not require modifying `ci.yml`.

Pull requests run the configured `review` checks in an unprivileged CI job: actionlint, Code Review, and the full Build/test suite. Forked or untrusted PR code cannot request the privileged bootstrap. Trusted `source` pushes run a guarded bootstrap that generates `pipeline.yml` and its component jobs on a temporary branch. It uses an installation App or explicitly configured bootstrap token, scopes job permissions to each task, then waits until the exact generated run completes before the permanent `validate` check can pass.

The authored workflow is the only YAML stored permanently under `.github/workflows/`. Generated YAML is temporary execution output. Generated publication branch prefixes must be permitted by the protected GitHub environments; publication currently defaults to the existing `ci/run-` prefix, while other operations may choose their own. Environment protections are not bypassed. All bootstrap credential values stay in GitHub, not JSON or generated Git.

On GitHub, `workflow_dispatch` accepts an operation name from the JSON catalog and a separate explicit `publish=true` approval for manual publication. The default is read-only `validation`. The `validate` job remains the required status check regardless of operation. Local `act` runs use the same routing and create generated workflows only in a disposable checkout – never by pushing a remote branch.

The underlying component planner, archived native adapters and Luau execution engine remain under `ci/`. `ci/bootstrap/routes.cjs` owns safe routing, and `ci/github/resources/branches/branchRun.luau` owns generated ref lifecycle, observation and cleanup. The previous hard-coded staged Publish jobs and standalone Code Review workflow have been removed.

**Credentials:** Job permissions and environment admission are determined by GitHub before code runs. Only the stable bootstrap transport has fixed fields; the alias names come from the JSON catalog. Component-specific bindings and roles are compiled dynamically for trusted generated jobs. A new role cannot elevate the bootstrap itself, and read-only PR checks do not receive any publication credentials.

The source ruleset should require the `validate` check from **CI**. If a legacy rule requires the standalone Code Review workflow, update that rule after merging; the Code Review job now belongs to CI.

## VS Code setup

Install the recommended [Workbench Bridge](https://marketplace.visualstudio.com/items?itemName=Kooraseru.workbench-bridge) extension when working in VS Code. The trusted workspace command starts `dependencies/packages/editor/editorIntegration/client.cjs`, which runs dependency setup and native preflight checks through the bridge. Setup progress, failures, checker findings, and reruns appear in the workspace status bar, output channel, and Problems panel. The same loader and checker remain available directly from the command line.

## Local CI and GitHub stages

Run the complete contributor validation path with one command from the repository root:

```sh
bash ci/run.sh
```

Run the normal unprivileged contributor path with `bash ci/run.sh`. It installs dependencies, executes the read-only Build component graph, then runs the repository test suites. Hosted review invokes these same checks and headless Preflight/Rules through the declared read-only route.

On a trusted source push, the launcher compiles the generated job graph instead of performing publication inline. Component output archives remain integrity-checked, credential environments stay isolated by job, and the required CI status reflects the *completed* generated run. Local GitHub Actions uses an isolated checkout and adapts artifact actions to v4 within that checkout only.

Local `act` read-only routes execute directly and do not require remote delegation; generated routes render an ephemeral Pipeline and execute it through the local artifact transport. Neither path changes the authored workflow file.

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

Manual dispatch defaults to read-only `validation`. Select the `publish` operation and approve `publish=true` to request source publication. Source pushes follow the configured `publish` route and use the generated branch, never the fixed-stage credential groups. The sample release and package conflict policies default to `skip`. Pages and attestation native integrations remain disabled until they are implemented.

The sample release and package conflict policies default to `skip`, not `replace`. To replace a tag, release, or package version, opt in explicitly after reviewing the generated outputs. Publication rehearsals route both GitHub API requests and release-asset uploads to the local test server. Pages and attestation components currently prepare inputs only; the fixed hosted CI workflow does not yet deploy Pages or sign attestations. Their sample settings are therefore disabled and treated as expected skips until native deployment/signing jobs are implemented and verified.

The default is `workflow_dispatch` with `operation=validation`. Explicit events, `--input operation=...`, dotenv input files, and event payloads are honored. Local Build automatically runs the generated controller and reusable Build workflow in an isolated checkout, then exports verified ordinary files. Publish is omitted locally. The launcher suppresses ambient GitHub-token discovery and default secret-file loading for local execution. Readiness needs explicit read authorization; no publication is performed as verification.

Current compiled outputs live under `build/artifacts/`; generated products stay under `build/github/`. Each invocation retains its own `build/run/<id>/outputs/` snapshot, Start and execution logs, stage reports, generated workflows, and internal transport archives. The previous successful current outputs remain intact after a failed run or export. Unowned or user-modified files cause an ownership conflict instead of being overwritten. The output manifest records paths, sizes, hashes, source revision, and the tracked working-copy digest.

Current-output ownership and v2 pipeline records live under ignored `.workspace/ci/`. Old v1 invocation records remain readable. Do not delete `.workspace/` as build cleanup. Archives are transport state; consumers inspect or launch the exported files directly.

## Headless code review

Pull requests into `source` run the configured `review` operation inside `.github/workflows/ci.yml` without opening an editor or exposing publication credentials. The workflow installs the project's managed checker dependencies and runs both Preflight (`--ci`) and repository Rules (`--rules`) through their existing CLIs. TypeScript, Lute, Bootstrap plan, and configured rule findings appear in GitHub job annotations and a summary. This does not include VS Code-only or extension-provided diagnostics unless a separate headless analyzer is configured.

The CI Code Review job uploads every diagnostic as `code-review-findings/diagnostics.json` plus `summary.md`. To avoid flooding review pages with existing warnings, only the first 50 findings affecting PR-changed files are annotated; the full report retains the rest. Errors in changed files or checker failures fail Code Review; existing errors in unrelated files are reported without blocking an unrelated pull request. Expected invalid rule fixtures are omitted from the counted diagnostics, while unexpected fixture outcomes remain errors. A manual workflow dispatch reviews the whole repository.

To run the same checks without GitHub or an editor, run `node dependencies/packages/core/dependencyLoader/index.ts` followed by `node ci/code-review.cjs`. The full report is written to `build/code-review/`.
