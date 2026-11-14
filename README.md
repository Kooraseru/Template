# Template

A reusable development workspace and CI foundation for packages, editor extensions, applications, and Luau projects. This repository is a **GitHub repository template**: consumers can keep its CI, rules, code review, dependency system, and editor integrations while replacing the project source.

## Create a repository (approximately ten-minute setup)

1. Select **Use this template → Create a new repository** on [Kooraseru/Template](https://github.com/Kooraseru/Template). Choose the owner, repository name, and visibility. Use only the template's default branch unless you deliberately need its generated branch fixtures.
2. Clone the new repository and run **\`node ci/template/setup.cjs\`** from its root. This offline check reports your repository identity, default-branch detection, Template version, branch-generation configuration, and missing settings. Node.js 24+ is recommended for the existing workspace dependency loader.
3. Edit **\`dependencies/dependencies.json\`** to declare your project's tools and packages, and **\`.github/config/targets.toml\`** for optional publishing destinations. \`github.repository = "current"\` automatically uses the repository running CI; there's no need to hardcode an organization or account.
4. Run **\`node dependencies/packages/core/dependencyLoader/index.ts\`**, then **\`bash ci/run.sh\`** for dependency setup and the full local validation path. When changing dependency declarations, run the loader once with \`--update-lock\` and commit both manifest and lock.
5. Replace the sample files under \`source/\` with your project code. Edit repository rules under \`rules/\` and editor behavior in \`.vscode/config/workflow.json\` only if necessary.

**No secrets are required for normal read-only CI.** GitHub Actions runs pull-request validation and default-branch validation by default; publishing remains an opt-in operation. You don't need to edit \`.github/workflows/ci.yml\` to add checks, components, or new build tools.

## CI and optional publishing

The one authored \`.github/workflows/ci.yml\` uses \`.github/config/ci/operations.json\` to select an operation. By default, new repositories run the unprivileged \`validation\` route on push and \`review\` on pull requests; the actual default branch is read from the GitHub event rather than assumed to be named \`source\`.

To enable trusted automatic publishing, edit \`.github/config/ci/operations.json\` and change \`triggers.push\` from \`validation\` to \`publish\`. Review \`.github/config/targets.toml\`, publication records under \`.github/config/publishing/\`, and the role/environment bindings in \`.github/config/credentials.json\`. Configure the \`ci-bootstrap\` GitHub environment and any declared secret or variable names through the repository's **Settings → Environments**. Never commit tokens.

The trusted bootstrap has \`id-token: write\` available for authenticated OIDC providers and supports scoped GitHub App/bootstrap credentials for native workflow generation. An OIDC JWT is not itself a registry credential: npm, extension marketplaces, or other services must independently support trusted publishing and recognize the repository/workflow identity. Unsupported publishing adapters are **not** automatically enabled. The current example GitHub Packages records are staging fixtures, not working npm/NuGet/RubyGems publisher adapters.

Manual **Run workflow** supports the \`validation\`, \`readiness\`, \`build\`, and \`publish\` operations; manual publication additionally requires the \`publish\` confirmation input. Read-only pull requests never receive publishing credentials. Publication permissions and the configured environment are still enforced by GitHub.

For internals and the local \`act\` path, see [CI documentation](ci/README.md).

## Generated branches

Branch creation has **not been removed**. The build component under \`ci/components/governance/branches/build/\` reads records from \`.github/config/branches/*.toml\`, including \`.github/config/branches/main.toml\`. It stages documentation and matching files under \`build/github/branches/<branch>/\`; the separate privileged branch publisher creates or updates remote branches if \`github.publication.branches = true\`.

Edit \`main.toml\` to control which source paths are copied to a generated \`main\` branch. If \`main\` is already the destination's default branch, publication skips it rather than overwriting the default branch. Other branches can be added by adding a TOML record; no additional authored GitHub workflows are needed.

## Template version and updates

\`.github/config/template.json\` records the installed **Template distribution** version and the upstream repository. Every repository created using GitHub's template feature inherits this file; it does not inherit the upstream's Git history.

Check for releases with:

\`\`\`sh
node ci/template/version.cjs
node ci/template/version.cjs --json
\`\`\`

This compares the recorded installed version against releases tagged \`template/vX.Y.Z\` in \`Kooraseru/Template\`. It reports \`current\`, \`update-available\`, \`ahead\`, \`unpublished\`, or \`unverifiable\`, and also writes an advisory GitHub Actions job summary when run in CI. Network failures do not block project builds.

The initial \`0.0.0\` is an **unreleased baseline**, not an invented \`template/v1.0.0\` tag. The first Template distribution must update this file in its release commit and tag that exact commit \`template/v1.0.0\` (or the chosen release version). Existing application releases such as \`0.1.0\` are not Template releases. Releases of the CI engine and consuming projects are independent.

Template-owned paths are listed in the version record for future reviewable upgrade patches. **Update detection does not merge, replace, or overwrite consumer files.** GitHub templates are not forks; updates require a reviewed change rather than a Git ancestry merge.

## Dependency maintenance

\`.github/dependabot.yml\` enables weekly GitHub Actions update pull requests. For a project that adds a standard package manifest such as \`package.json\`, \`Cargo.toml\`, or \`pyproject.toml\`, add the appropriate Dependabot ecosystem and directory entry. GitHub does not automatically support the custom \`dependencies/dependencies.json\` format.

The existing dependency loader owns custom providers and pins in \`dependencies/dependencies.lock\`. To update those, edit the declarations, run \`--update-lock\`, and review the lockfile changes. To update pinned GitHub Actions in \`.github/workflows/actions.lock\`, run the configured actions-lock tool through the dependency loader and commit the regenerated lock.

## VS Code and diagnostics

Install the recommended [Workbench Bridge](https://github.com/Kooraseru/workbench-bridge) extension for status-bar dependency setup, Preflight, rules diagnostics, and editor integration. The \`.vscode/config/workflow.json\` configuration owns editor commands and watch paths. No editor installation is needed for headless CI.

For a machine-readable onboarding report, use \`node ci/template/setup.cjs --json\`. For a local validation run, use \`bash ci/run.sh\`. For local GitHub Actions, use \`node dependencies/packages/ci/localActions/run.cjs\`.

See [workspace dependencies](dependencies/README.md), [rules](rules/README.md), and [CI implementation](ci/README.md) for detailed contracts.
