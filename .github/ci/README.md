# CI implementation

`.github/workflows/ci.yml` is the committed workflow. It invokes the Luau coordinator at `.github/ci/entry.luau`, which discovers component manifests under `.github/ci/components/` and schedules isolated component runs. Grouping folders do not establish order; dependencies come from declared capabilities.

Edit CI behavior and component implementations under `.github/ci/`. Edit scheduler policy, credentials-by-name, response templates, and tool pins under `.github/automation/`. GitHub API integrations are grouped under `.github/ci/integrations/github/`. Native GitHub job adapters remain beside the component that owns them in `github.toml` files.

## VS Code setup

Install the recommended [Workbench Bridge](https://marketplace.visualstudio.com/items?itemName=Kooraseru.workbench-bridge) extension when working in VS Code. The trusted workspace command starts `dependencies/packages/editorIntegration/client.cjs`, which runs dependency setup and native preflight checks through the bridge. Setup progress, failures, checker findings, and reruns appear in the workspace status bar, output channel, and Problems panel. The same loader and checker remain available directly from the command line.

## Dependencies and local checks

`dependencies/dependencies.toml` declares dependency sources and output locations; `dependencies/dependencies.lock` pins upstream versions and assets. Checked-in local tools live under `dependencies/packages/`, including `dependencyLoader`, `dataFormats`, and `ruleLinter`.

Install or refresh all declared dependencies and generate the local config discovery bridges with:

```sh
node dependencies/packages/dependencyLoader/index.ts
```

After changing dependency versions or sources in the manifest, refresh the lock and run setup again:

```sh
node dependencies/packages/dependencyLoader/index.ts --update-lock
node dependencies/packages/dependencyLoader/index.ts
```

Run a command through the loader so its dependencies are available first:

```sh
node dependencies/packages/dependencyLoader/index.ts --exec luau.lute --version
node dependencies/packages/dependencyLoader/index.ts --exec luau.lute check .github/ci/entry.luau
node dependencies/packages/dependencyLoader/index.ts --exec luau.lute lint .github/ci
```

The loader writes managed package/runtime files to `build/dependencies/packages/`, executables to `build/dependencies/binaries/`, and generated type definitions to `build/dependencies/types/`. These build outputs are ignored. Local source packages stay checked in under `dependencies/packages/`.

## Configuration

Edit the canonical Luau config at `.vscode/config/luau/.luaurc` and the canonical TypeScript config at `.vscode/config/typescript/tsconfig.json`. Dependency setup generates root `.luaurc` and `tsconfig.json` discovery bridges for command line tools and editors. Those root bridges are ignored and hidden from Explorer; change the canonical configs instead. TypeScript includes `.ts`, `.tsx`, `.mts`, and `.cts` files across the repository, with generated output and external packages excluded. Luau strict checking is enabled in the canonical config, and TypeScript strict checking is enabled in its canonical `tsconfig.json`.

## Workflow Preflight

From the repository root, install the managed tools and the pinned Preflight package:

```powershell
node dependencies/packages/dependencyLoader/index.ts
npm --prefix dependencies ci --ignore-scripts
```

Analyze the actual Bootstrap graph for an event:

```powershell
node dependencies/node_modules/preflight/bin/preflight.js plan --provider .github/ci/preflight/provider.cjs --entry pull_request
```

For a release plan, use `--entry push --target distribution/releases/publish`. Preflight includes the selected task's upstream dependencies. Plan analysis resolves the graph without running its tasks.

To show the pull-request plan in VS Code, add this command to the workspace's `workbenchBridge.workspaceCommands` after installing the package:

```json
["node", "dependencies/node_modules/preflight/bin/preflight.js", "workspace", "--provider", ".github/ci/preflight/provider.cjs", "--bridge-client", "dependencies/packages/workbenchBridgeClient"]
```
