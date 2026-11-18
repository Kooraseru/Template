# Template

A reusable development workspace and CI foundation for packages, editor extensions, applications, and Luau projects. This repository is a **GitHub repository template**: consumers can keep its CI, rules, code review, dependency system, and editor integrations while replacing the project source.

## Create a repository (approximately ten-minute setup)

1. Select **Use this template → Create a new repository** on [Kooraseru/Template](https://github.com/Kooraseru/Template). Choose the owner, repository name, and visibility. Use only the template's default branch unless you deliberately need its generated branch fixtures.
2. Clone the new repository and run **`node .github/components/quality/setup/readiness.cjs`** from its root. This offline check reports your repository identity, default-branch detection, Template version, branch-generation configuration, and missing settings. Node.js 24+ is recommended for the existing workspace dependency loader.
3. Edit **`dependencies/dependencies.json`** to declare your project's tools and packages, and **`config/targets.toml`** for optional publishing destinations. `github.repository = "current"` automatically uses the repository running CI; there's no need to hardcode an organization or account.
4. Run **`node dependencies/packages/core/dependencyLoader/index.ts`**, then **`node dependencies/packages/core/dependencyLoader/index.ts --exec tools.ciEngine native-validate`** for dependency setup and the full local validation path. When changing dependency declarations, run the loader once with `--update-lock` and commit both manifest and lock.
5. Replace the sample files under `source/` with your project code. Edit repository rules under `rules/` and editor behavior in `.vscode/config/workflow.json` only if necessary.

**No secrets are required for normal read-only CI.** GitHub Actions validates pull requests and source-branch pushes. Default-branch pushes validate; publication requires an explicitly authorized operation. Configure GitHub Pages with **Source: GitHub Actions** in repository settings. The CI controller does not need modification to add components.

## CI and optional publishing

The push, pull, manual and remote event workflows submit independent CI Engine requests. PR close only retires an existing preview. `bootstrap.yml` pins the engine once. `config/ci/operations.json` declares the selected components and optional native test matrix.

Generated `main` and Pages publication use scoped same-run component jobs and their toggles under `config/targets.toml`. Configure named credentials in the declared environments.

The trusted bootstrap has `id-token: write` available for authenticated OIDC providers and supports scoped GitHub App/bootstrap credentials for native workflow generation. An OIDC JWT is not itself a registry credential: npm, extension marketplaces, or other services must independently support trusted publishing and recognize the repository/workflow identity. Unsupported publishing adapters are **not** automatically enabled. The current example GitHub Packages records are staging fixtures, not working npm/NuGet/RubyGems publisher adapters.

Manual **Run workflow** supports `validation`, `readiness`, `build`, and `publish`; manual publication also requires explicit `publish` confirmation. Read-only pull requests receive no publishing credentials. The external engine owns the workflow lifecycle, artifact transport and scoped publication jobs. No temporary execution branches are created.

The authored documentation and locale records live under [`content/`](content/docs/index.md), with formatting rules in [`content/docs/authoring.md`](content/docs/authoring.md). MkDocs is intentionally not configured yet.

For internals and the local `act` path, see [CI documentation](.github/components/README.md).

## Generated branches

Branch creation has **not been removed**. The build component under `.github/components/governance/branches/build/` reads records from `config/branches/*.toml`, including `config/branches/main.toml`. It stages documentation and matching files under `build/github/branches/<branch>/`; the separate privileged branch publisher creates or updates remote branches if `github.publication.branches = true`.

Edit `main.toml` to control which source paths are copied to a generated `main` branch. If `main` is already the destination's default branch, publication skips it rather than overwriting the default branch. Other branches can be added by adding a TOML record without introducing another publication workflow.

## Template version and updates

`config/template.json` records the installed **Template distribution** version and the upstream repository. Every repository created using GitHub's template feature inherits this file; it does not inherit the upstream's Git history.

Check for releases with:

```sh
node .github/components/quality/template-updates/version.cjs
node .github/components/quality/template-updates/version.cjs --json
```

This compares the recorded installed version against releases tagged `template/vX.Y.Z` in `Kooraseru/Template`. It reports `current`, `update-available`, `ahead`, `unpublished`, or `unverifiable`, and also writes an advisory GitHub Actions job summary when run in CI. Network failures do not block project builds.

The initial `0.0.0` is an **unreleased baseline**, not an invented `template/v1.0.0` tag. The first Template distribution must update this file in its release commit and tag that exact commit `template/v1.0.0` (or the chosen release version). Existing application releases such as `0.1.0` are not Template releases. Releases of the CI engine and consuming projects are independent.

Template-owned paths are listed in the version record for future reviewable upgrade patches. **Update detection does not merge, replace, or overwrite consumer files.** GitHub templates are not forks; updates require a reviewed change rather than a Git ancestry merge.

## Dependency maintenance

`.github/dependabot.yml` enables weekly GitHub Actions update pull requests. For a project that adds a standard package manifest such as `package.json`, `Cargo.toml`, or `pyproject.toml`, add the appropriate Dependabot ecosystem and directory entry. GitHub does not automatically support the custom `dependencies/dependencies.json` format.

The existing dependency loader owns custom providers and pins in `dependencies/dependencies.lock`. To update those, edit the declarations, run `--update-lock`, and review the lockfile changes. External reusable workflows are pinned by full commit SHA in the event workflows; CI-Engine's own action lockfile covers the actions invoked by that reusable workflow. Template's local action lockfile is separate.

## VS Code and diagnostics

Install the recommended [Workbench Bridge](https://github.com/Kooraseru/workbench-bridge) extension for status-bar dependency setup, Preflight, rules diagnostics, and editor integration. The `.vscode/config/workflow.json` configuration owns editor commands and watch paths. No editor installation is needed for headless CI.

For a machine-readable onboarding report, use `node .github/components/quality/setup/readiness.cjs --json`. For a local validation run, use `node dependencies/packages/core/dependencyLoader/index.ts --exec tools.ciEngine native-validate`. For local GitHub Actions, use `node dependencies/packages/core/dependencyLoader/index.ts --only tools.ciEngine --exec tools.ciEngine`.

See [workspace dependencies](dependencies/README.md), [rules](rules/README.md), and [CI implementation](.github/components/README.md) for detailed contracts.


### Native validation

A push or PR dispatches one independent CI Engine execution. It cross-compiles the declared hosts, executes the universal regression suite, and uploads the resulting binaries within that same run. Host tests run on a matrix discovered from the tracked host contracts. The final gate requires both the build and every native test to pass. Validation creates no temporary workflow branches and requires no write credentials.

Explicit publication and preview deployment use scoped jobs inside the same independent engine run. They are not triggered by ordinary validation.

