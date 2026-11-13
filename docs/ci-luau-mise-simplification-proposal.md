# RFC: simplify CI around Luau and externally managed dependencies

Status: **Proposal only — no runtime migration or deployment**
Stack: source <- proposal/ci-linear-executor <- proposal/ci-luau-mise-simplification
Parent: [Linear CI controller RFC](./ci-linear-executor-proposal.md)

## Goal and decision criteria

The goal is **less infrastructure owned and maintained by Template**. File count is not itself an objective; removing tests or concatenating modules to hit a percentage is explicitly not a solution. External dependencies can be implemented in any language. Template-authored CI remains predominantly **Luau + Lute**, using the existing recursive modules and init.luau conventions.

Before adding owned code, ask: does a tested dependency already provide the behavior? Can it be configured directly? Is the remaining glue truly Template-specific (component policy, provenance, authorization, reporting)? Only introduce a new implementation language if a feature genuinely requires it. No Go controller rewrite.

## Preserve the eight-job contract and one execution graph

The existing permanent .github/workflows/ci.yml stays a **strict linear chain**:

~~~mermaid
flowchart LR
    A["Setup Dependencies"] --> B["Resolve Operation"] --> C["Check Permissions"] --> D["Generate Pipeline"] --> E["Run Pipeline"] --> F["Collect Results"] --> G["Cleanup"] --> H["Validate"]
~~~

Adding a new component, audit, operation, test, or publication target must not modify the authored workflow. Generate Pipeline produces a separate dynamically compiled workflow/DAG, including parallel and conditional jobs. Run Pipeline **executes that workflow**, not a second hand-authored command graph.

The current PR #42 read-only execution uses the CJS runLocal scheduler rather than its generated workflow. This is a known architectural defect: the next implementation must retire it, not translate it into Luau. Local act and hosted GitHub Actions are different transports of the **same generated workflow**. Untrusted PRs must remain segregated from privileged environment credentials; local act is not an authorization bypass.

## Dependencies: one authority

**Mise owns all external tool version resolution, installation and lock state.** Native package managers are permitted underneath it when appropriate (npm for JS-based checker dependencies, for example). Template must not retain an additional custom provider registry, GitHub release downloader, archive parser, platform resolver, lock engine, or npm installation system.

Preserve the existing directory roles:

~~~text
dependencies/
├── managed/                  # Installed external tools/packages/state (ignored)
├── packages/                 # Packages maintained by this repository
│   ├── checks/
│   ├── ci/
│   ├── core/
│   └── editor/
├── mise.toml                 # Proposed authoritative dependency config
└── mise.lock                 # Proposed native Mise lockfile
~~~

Mise itself is an external executable, installed normally or delivered in a prepared image. Its installed tools and data can be directed into dependencies/managed (for example MISE_DATA_DIR or MISE_INSTALLS_DIR where appropriate). Mise must never be committed into dependencies/packages as if it were one of our source modules.

**Important config-path caveat:** Mise does not automatically discover dependencies/mise.toml when launched from the repository root. The explicit -C / --cd option selects the directory, but also changes the working directory. A migration spike must prove an invocation contract for local, VS Code and CI that both loads this config and runs Luau code with correct repository-root path semantics, without duplicating configuration files or inventing a shell dispatcher. The old MISE_CONFIG_FILE variable is not a project-file override to assume.

Known existing loader features requiring parity evidence:

| Current implementation | Desired owner / acceptance gate |
| --- | --- |
| GitHub-release Lute, Pandoc and actions-lock binaries | Mise GitHub/aqua/native backend; verify pinned asset/platform selection |
| Lute setup, .luaurc aliases and exported types | Native supported post-install/setup mechanism; verify resulting alias and type layout |
| Workspace npm and Preflight tools | Native package manager provisioned through Mise; prove repeatable lock behavior |
| SHA-256 verification and dependency lockfile | Mise native lock + strict installation, including non-semver releases |
| Windows ARM64, Linux AMD64 and ARM64 | Test real asset availability and execution, not merely install success |
| Atomic publish, stale state and managed ownership | Prefer native Mise lifecycle; one-time migration only where necessary |
| VS Code setup/notifications | Editor integration invokes external tooling; no second installer |
| Locally maintained packages under dependencies/packages | Keep in source; do not copy them just to register tools |

**Deletion gate:** Only after proven parity remove dependencies/dependencies.json, dependencies.lock, dependencies.schema.json and the TypeScript loader, its archive code and vendored libraries if no longer referenced. Do not keep two authoritative dependency declarations as a hidden fallback.

Pin and test a specific Mise release, including actual lockfile behavior. Before cutover, verify every tool in the existing dependency manifest and its artifact paths.

## Module layout: reuse rather than add another framework

Target shape is a logical ownership map. Do not create files just because the example shows directories. Reuse existing Luau modules and init.luau conventions:

~~~text
ci/
├── init.luau                         # One top-level CI interface
├── controller/
│   └── init.luau                     # Eight-stage coordination, if not owned elsewhere
├── bootstrap/
│   ├── init.luau
│   ├── contracts/
│   ├── discovery/
│   └── planning/
├── components/
│   └── <group>/<component>/
│       ├── component.toml
│       └── init.luau                 # Only for custom Luau behavior
└── github/
    ├── init.luau
    ├── authentication/
    ├── workflows/
    ├── reporting/
    ├── publication/
    └── resources/
~~~

Keep the existing Luau component contract, discovery, capability DAG planner, workflow renderer, native-job adapter, reporting and GitHub domain logic **where it implements repository-specific policy**. Remove the CJS controller, CJS routes, alternate scheduler, and redundant GitHub authentication integrations after their last callers have moved. Avoid a Go rewrite of working Luau code.

External tools should directly own established work:

| Responsibility | Tool / native capability | Template-owned remainder |
| --- | --- | --- |
| Tool install/versions/lock | Mise + native package managers | Tool selection and platform acceptance |
| Workflow syntax | actionlint | Which generated files must pass |
| GitHub action lock | gh-actions-lock | Workflow provenance and launch policy |
| GitHub API and branch operations | gh CLI or existing Lute HTTP client | Allowed target, ownership, error handling |
| GitHub App credentials | Scoped create-github-app-token action in authorized job | Capability/environment selection, no secret value enumeration |
| Hosted artifacts | Official artifact actions | Type, identity, digest and report interpretation |
| Local generated workflow DAG | act | Trust policy, source identity, result verification |
| Component discovery, DAG, outputs and skip rules | Existing Luau modules | Template-specific behavior |
| External linting/checking | Existing checker dependencies, regardless of language | Severity and component outcomes |

Do not replace direct Lute HTTP calls with a gh wrapper when the latter increases code. Do not introduce a package wrapper solely to change a program's command name.

## Configuration: optimize for non-programmers

A user should be able to enable/disable components and select operations without knowing Luau, editing CI YAML, or understanding the graph's internal scheduling.

**Format policy:**

- **TOML** for authored, human-facing Template settings: operations, component selection/enabling, skip policy, credential aliases/capabilities, labels and publication defaults.
- **JSON** for complex GitHub-native structures such as project field/view definitions and rulesets; also JSON Schema and machine-readable contracts. Do not invent TOML translations for near-native API documents.
- **YAML** for GitHub Actions and other externally dictated formats.
- Keep **native formats** for VS Code, Lute (.luaurc) and Mise.
- Generated locks, manifests and outputs are not human-facing settings; no stored secret values.

Existing CI options are split among operations.json, components.toml and execution.toml. Proposed user-facing consolidation:

~~~text
.github/
├── workflows/
│   ├── ci.yml
│   └── actions.lock
└── config/
    ├── ci/
    │   └── settings.toml            # Event routes, operations, component switches, skip policies
    ├── credentials.toml             # Secret/variable ALIASES and capability policy, not values
    ├── jobs/                        # Advanced component job overrides
    ├── issues/                      # TOML authored labels
    ├── projects/                    # JSON API-shaped definitions
    ├── rulesets/                    # JSON API-shaped definitions
    ├── publishing/
    └── reports/
~~~

Illustrative settings only, not a current parser contract:

~~~toml
[events]
push = "publish"
pull_request = "review"
workflow_dispatch = "validation"

[operations.review]
components = ["quality/code-review", "quality/rules-audit"]
mode = "readonly"

[operations.validation]
components = ["*"]
mode = "readonly"

[operations.publish]
components = ["*"]
mode = "generated"
publication = true

[components]
default = true

[components.enabled]
"work/projects/sync" = false

[execution.skip]
default = "neutral"

[execution.skip.components]
"distribution/packages/publish" = "success"
~~~

An asterisk selects only components eligible for the event, phase, and trust boundary. Dependencies are included via the existing planner's capability closure. Reject missing providers, cycles, illegal privilege transitions, output ownership conflicts, unknown components and unsafe event mappings. A publication flag cannot authorize publication from a PR.

Do not copy the current operations.json command arrays into TOML; that would preserve the second scheduler. A generic command component may invoke a third-party checker without requiring an init.luau file; only special logic needs custom Luau.

Use a mature TOML language server and schema-based completion where possible (for example Taplo); do not build an editor schema framework. Existing rule fixtures may remain colocated. New CI-wide infrastructure tests should be grouped rather than introducing one new .test.cjs or independent bash entry point for every operation.

## Execution environment and artifact transport

Github-hosted jobs use separate runners. Avoid reinstalling Node, downloading a large dependency archive, or unpacking it in every stage just to parse a manifest. Use a prebuilt immutable image **if profiling shows it reduces cost**; build that image only when its toolchain changes. Container support is an implementation detail of dependency delivery, not another user-facing system.

The generated workflow is the authoritative scheduling graph under both GitHub Actions and act. It must be validated, locked for hosted execution, tied to its source revision, and executed without implicit privilege escalation.

Each stage should pass only the manifests/digests it owns, using official artifact transport; do not recursively upload inherited manifests, merge overlapping snapshots, or confuse self-consistency with upstream provenance. Collect must report component evidence, not just remote run metadata. Always attempt cleanup and the final required validate check even after earlier failures.

Preserve original failure/cancellation/timeout evidence; do not launder it through a green Collect Results job. Privileged environment secrets are available only in their authorized jobs. GitHub environments cannot be dynamically enumerated for secret values.

## Migration sequence

1. Freeze a baseline from PR #42; inventory all external tools, loader outputs, editor callers, component operations, credentials and execution contracts. Record runtime overhead.
2. Validate Mise replacement using a focused platform matrix and existing Lute aliases/types. Decide the project-config discovery/working-directory contract before committing an invocation.
3. Adopt Mise as the sole external dependency authority; keep the old loader only during a bounded migration and then remove its consumers and manifests.
4. Reuse Luau init modules to implement the controller's unavoidable Template-specific stage logic; delete CJS routes/controller/credential wrappers after parity.
5. Eliminate runLocal and all alternative DAG schedulers. Execute generated workflow files via act locally and GitHub Actions hosted.
6. Merge CI user settings into a schema-validated TOML entry point; keep JSON and YAML where external tools own the format.
7. Verify failures, cancellations, artifact provenance, credential binding, reporting, safe branch cleanup, multiple architectures and local/hosted consistency.
8. Remove obsolete source files and compatibility paths **only when no caller depends on them**; keep distinct rule fixtures and tests that enforce valid behavior.

## Acceptance criteria

- [ ] Exactly one permanent eight-job .github/workflows/ci.yml; new operations never edit it.
- [ ] The **actual generated workflow DAG** executes under both act and GitHub Actions; no alternate command scheduler.
- [ ] Mise is the sole owner of external dependency resolution, installation and locking; no second Template-maintained dependency loader.
- [ ] External installs stay in dependencies/managed; authored packages stay in dependencies/packages.
- [ ] Luau/Lute remains the primary owned CI implementation; init.luau module convention preserved.
- [ ] A non-programmer can configure operations, components, policy with validated declarative settings.
- [ ] JSON/YAML/native formats remain where required by external systems.
- [ ] All existing supported tools/platforms and CI component behavior have parity.
- [ ] PRs remain read-only, credentials are environment-scoped, reports remain honest, temporary refs are safely cleaned.
- [ ] Hosted and local end-to-end verification, plus an expressly safe trusted rehearsal before merge.

## Non-goals

No Go controller rewrite, no mandatory removal of JS-based third-party tools, no editor extension host rewrite, no new service/daemon, no artificial test or file count reduction. No merge, source-branch edits, credential changes, or publication is authorized by this proposal.

References: [Mise project config discovery](https://mise.jdx.dev/configuration), [Mise native backends](https://mise.jdx.dev/dev-tools/backends/), [Mise lockfiles](https://mise.jdx.dev/dev-tools/mise-lock.html), and [Mise installation directory controls](https://mise.jdx.dev/configuration/environment-variables.html).
