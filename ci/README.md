# CI implementation

`.github/workflows/ci.yml` is the committed workflow. It invokes the Luau coordinator at `ci/entry.luau`, which discovers component manifests under `ci/components/` and schedules isolated component runs. Grouping folders do not establish order; dependencies come from declared capabilities.

Edit CI behavior and component implementations under `ci/`. Edit credential names and publication switches in `.github/config/targets.toml`. Scheduler policy, reports, and permissions live under `.github/config/`. GitHub API integrations are grouped under `ci/github/`. Native GitHub job adapters are keyed by component identity under `.github/config/jobs/`. Draft adapters are kept under `jobs/drafts/`.

## VS Code setup

Install the recommended [Workbench Bridge](https://marketplace.visualstudio.com/items?itemName=Kooraseru.workbench-bridge) extension when working in VS Code. The trusted workspace command starts `dependencies/packages/editor/editorIntegration/client.cjs`, which runs dependency setup and native preflight checks through the bridge. Setup progress, failures, checker findings, and reruns appear in the workspace status bar, output channel, and Problems panel. The same loader and checker remain available directly from the command line.

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

The loader writes managed package/runtime files to `build/dependencies/packages/`, executables to `build/dependencies/bin/`, and generated type definitions to `build/dependencies/types/`. These build outputs are ignored. The npm provider writes its manifest, native lock, and install to build/dependencies/npm/. See the [dependency provider contract](../dependencies/README.md). Local source packages stay checked in under `dependencies/packages/`.

## Configuration

Edit the canonical Luau config at `.vscode/config/luau/.luaurc` and the canonical TypeScript config at `.vscode/config/typescript/tsconfig.json`. Dependency setup generates root `.luaurc` and `tsconfig.json` discovery bridges for command line tools and editors. Those root bridges are ignored and hidden from Explorer; change the canonical configs instead. TypeScript includes `.ts`, `.tsx`, `.mts`, and `.cts` files across the repository, with generated output and external packages excluded. Luau strict checking is enabled in the canonical config, and TypeScript strict checking is enabled in its canonical `tsconfig.json`.

## Workflow Preflight

From the repository root, install the managed tools and the pinned Preflight package:

```powershell
node dependencies/packages/core/dependencyLoader/index.ts
```

Analyze the actual Bootstrap graph for an event:

```powershell
node build/dependencies/npm/node_modules/preflight/bin/preflight.js plan --provider dependencies/packages/checks/preflightChecker/bootstrap/provider.cjs --entry pull_request
```

For a release plan, use `--entry push --target distribution/releases/publish`. Preflight includes the selected task's upstream dependencies. Plan analysis resolves the graph without running its tasks.

To show the pull-request plan in VS Code, add this command to the workspace's `workbenchBridge.workspaceCommands` after installing the package:

```json
["node", "build/dependencies/npm/node_modules/preflight/bin/preflight.js", "workspace", "--provider", "dependencies/packages/checks/preflightChecker/bootstrap/provider.cjs", "--bridge-client", "dependencies/packages/editor/workbenchBridgeClient"]
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
