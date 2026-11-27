# Template

A reusable development workspace for applications, packages, and Luau projects. GitHub Actions runs the pipeline directly; no separate scheduler, generated workflow, or legacy scheduler installation is required.

## Get started

1. Create a repository using [Template](https://github.com/Kooraseru/Template), clone it, and install Node.js 24 and Git.
2. Run the readiness check and dependency setup:

   ```sh
   node .github/components/quality/setup/readiness.cjs
   node dependencies/packages/core/dependencyLoader/index.ts
   ```

3. Replace the example source and host contracts in `source/`. Modify `.github/workflows/ci.yml` to match your project's build and test commands.
4. Run local checks or push a PR:

   ```sh
   node dependencies/packages/checks/preflightChecker/index.ts
   node dependencies/packages/checks/preflightChecker/index.ts --rules
   node dependencies/packages/checks/testSuites/run.cjs
   ```

The example Windows builds use Docker. For local host builds, run `node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run .github/components/source/build/run.luau`. Local Actions emulation uses the optional `act` task; hosted Windows tests require their native runners.

## GitHub Actions

- **CI:** read-only checks, host builds and tests, documentation, distribution staging, and a final `CI Required` check.
- **Publish:** select `rehearse`, `releases`, `branches`, or `pages` from Run workflow. Rehearsal never writes externally. Real publication requires an explicit selection on the default branch.
- **Maintenance:** validate or reconcile labels and planned milestones.
- **PR Results:** trusted review comments and Cloudflare preview publication from completed CI artifacts. Closing a PR retires its preview.

The shared documentation renderer and parity tooling are installed by the dependency loader. Reusable release, branch and documentation preview actions are pinned directly to reviewed commits of [CI-Packages](https://github.com/Kooraseru-Hub/CI-Packages). They are independent packages, not a scheduler.

For real publication, configure a protected `ci-publication` environment restricted to the authored default branch. Pages uses the `github-pages` environment and **Settings → Pages → Source: GitHub Actions**. Cloudflare previews use the separate `ci-preview-cloudflare` environment. Ordinary CI requires no publishing secrets.

## Configuration

| Path | Purpose |
| --- | --- |
| `.github/workflows/` | Native workflow and job definitions |
| `dependencies/dependencies.json` and `dependencies/dependencies.lock` | Workspace tools and pinned dependencies |
| `source/` | Project and host definitions |
| `rules/` | Project-owned rule linter definitions |
| `config/publishing/releases/settings.json` | Shared release settings |
| `releases/` | Version records and release notes |
| `config/branches/` | Generated branch source globs |
| `content/docs/` and `content/images/` | This project's Starlight documentation and assets |

Edit the workflow and commands for the consuming project rather than conforming to a protected template layout. The package staging fixtures do not implement a registry-specific publisher.

## Editor and updates

Install [Workbench Bridge](https://github.com/Kooraseru/workbench-bridge) for dependency setup, Preflight and rule diagnostics. Edit `.vscode/config/workflow.json` to customize the commands. Update workspace dependencies with the loader's `--update-lock` option and commit the manifest and lock together.

Check available Template releases using `node .github/components/quality/template-updates/version.cjs`. Updates are advisory; they do not overwrite project files.

See [CI implementation](.github/components/README.md), [workspace dependencies](dependencies/README.md), and [documentation](content/docs/index.md).
