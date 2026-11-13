# CI architecture and operating rules

GitHub configuration lives under `.github/`. CI implementation lives under root `ci/`. The single authored ci.yml routes source Build/Publish, Validation, and Readiness through `ci/init.luau`. Bootstrap owns planning and scheduling.

## Discovery and component contracts

The Luau bootstrap recursively discovers components under `ci/components/`. A component is identified by its path relative to that directory and owns `component.toml`. Read-only commands may be declared directly in its manifest; otherwise it owns `init.luau` and any private implementation modules. These two invocation modes are mutually exclusive. Grouping folders do not impose order. Capability declarations determine dependencies; the planner sorts them, detects cycles, validates output ownership and event boundaries, then executes in isolated child processes. Preserve skip, failure, blocked-dependency, and report behavior.

`.github/config/ci/settings.toml` contains event routing, component toggles, and execution policy; it does not define a component inventory. Do not add central component inventories. Update identities and any identity references in skip policy, reports, generated job IDs, and workflows whenever a component moves.

Host build implementations belong under `source/hosts/<host>/`. The source build component discovers `host.toml` files, loads the adjacent `init.luau`, and checks all declared artifact paths. Hosts own their toolchain, artifact list, and optional launch artifact. The CI launcher does not maintain host names or executable lookups and must work when a project has no launchable application.

## Workflow execution and trust boundaries

Pull requests use the same discovery and plan as source pushes but execute only read-boundary components. Fork pull requests receive no privileged credentials. Protected GitHub operations remain restricted to trusted source pushes and the existing publication settings. The `gate` result must reflect completed component execution, not just successful scheduling.

When native execution is available, generated jobs preserve declared dependency edges and exchange the actual component artifacts. Generated workflow files and execution branches are temporary run output. Never write generated commits to the trusted `source` branch. If native scheduling fails after privileged credentials are acquired, report failure instead of silently switching execution modes. Local `act` runs remain unauthenticated and use the same generated execution workflow and artifact boundaries.

Components declare `phase = "build"` or `phase = "publish"` independently of authority. Build is read-only and cannot require credentials or depend on Publish; Publish owns all external changes.

Generated output belongs under ignored `build/`. Compiled products use `build/artifacts/`; per-run stage logs, readable snapshots and transport bundles use `build/run/<id>/`. Installed dependencies remain under `dependencies/managed/`, and persistent records/ownership under `.workspace/`. GitHub products use `build/github/`; workflow-specific logs, responses, artifacts, dependency caches, and local action artifacts use `build/run/`. Producers, artifact uploads, and consumers must agree on exact paths. Create optional output folders only when a component actually produces output; a skipped component must not leave a passing or misleading artifact.

## GitHub configuration and operations

Configuration and authored records live with their owner:

- `.github/config/targets.toml` stores repository identity, aliases, and publication policy.
- `.github/config/branches/` contains one branch source record per branch.
- `.github/config/rulesets/` contains desired ruleset records.
- `.github/config/issues/` owns labels and milestones. `.github/config/projects/` owns project blueprints.
- `.github/config/publishing/` owns release, package, and attestation records.
- `.github/publication/` owns Pages and Wiki publication settings when supported.
- `.github/config/ci/` owns CI policy. Credential roles and permissions live in `config/credentials.json`. Report templates live in `config/reports/`.

Discover records from their owner directory. Adding a host, milestone, branch, project, ruleset, release, or package record should not require a CI registry edit. Malformed present records fail with a path-specific diagnostic. Preserve user project items, fields, options, and views during reconciliation. Preserve the existing source-gate and source-admin enforcement semantics. Do not treat planned Wiki ownership as implemented publication.

Use the shared GitHub integration for capability validation, target resolution, known permission requirements, credential selection, remote reads, reconciliation, and structured outcomes. Keep domain-specific desired-state logic in its resource module. Prefer `gh`, `gh api`, and native Actions features for common transport, pagination, and authentication. Do not expose unrestricted privileged requests through authored configuration. Permission messages should be actionable while acknowledging that GitHub errors do not always identify missing permissions unambiguously.

`GITHUB_TOKEN` is the default credential when its declared permissions suffice. Optional App/PAT credentials are referenced by secret or variable name only; values remain in GitHub Secrets or another secure provider. Missing optional authorization is a reported skip or authorization block with setup guidance. Never write tokens or private keys into artifacts or logs. Keep PR and fork execution unprivileged.

The Packages publisher currently stages package metadata but has no complete registry publication adapter. Report it as unsupported/skipped; a folder alone is not proof of publication. Pandoc remains required by the Pages renderer unless a replacement is separately validated against the same output behavior.

## Editor and language tools

`.vscode/` owns Luau LSP settings, Lute rules and configuration, Preflight's editor plan, tasks, and extension recommendations. The root `.luaurc` provides runtime module aliases and definitions. CI lint and editor diagnostics should share the same custom Lute rules. Preflight diagnoses editor state and does not replace the CI scheduler. Keep local shell hooks compatible with MSYS2, including Windows ARM64; do not introduce WSL or PowerShell runtime dependencies.

## Validation and reporting

Before changing paths, inspect their producers, consumers, workflow commands, imports, schemas, editor settings, globs, and generated artifacts. Validate Luau, TOML, JSON, shell, and workflow syntax; resolve imports; discover and plan every component; and check deterministic dependency ordering and output conflicts. Run the local `act` workflow when requested and available. Report only operations that actually executed. An empty-template run covers only bootstrap and discovery; it does not demonstrate builds, publication, or integrations that were skipped.
