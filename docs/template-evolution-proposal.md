# Template evolution – versioning, CI ownership, and project test extension

Status: **proposal and validation experiment**, not an activated template upgrade service.

Baseline: `source` merge `2114968dcce59df12561cce48fb0376984c9b12c` (PR #40). This document deliberately does **not** reclassify the sample project release `0.1.0` as a Template release.

## Decision summary

1. Maintain **four independent identities**: Template distribution, dependency resolutions, serialized contracts, and a consuming project's software publications. Never derive one from another.
2. Use **Semantic Versioning for stable Template distributions** and an exact upstream Git SHA for provenance. The Template's first published version is *not yet assigned*. Prefix Template tags (`template/vX.Y.Z`) so they cannot collide with consuming-project release tags such as `0.1.0`.
3. Prefer **stable pinned upstream dependencies with checked hashes**, upgrading them in reviewed PRs. This PR experiments with Lute `v1.0.0`; accept that downgrade **only if the complete hosted build, tests, editor/CI fixtures and local workflow pass**. On a regression, revert both dependency manifest and lock to the previous nightly.
4. Retain **shape-based contracts**. Permit **positive integer format versions** only where persisted, serialized records require unambiguous interpretation or migrations; reject unknown versions with actionable diagnostics. Do not use format numbers as proof of authorization, capability support, or structural correctness.
5. Keep a stable, minimal **authored GitHub Actions launcher**. Component selection, task dependencies, publication groups, and credential names must be owned by repository manifests and a controlled generator, **not written into `.github/workflows/ci.yml` per feature**.
6. Add a project-owned test extension point separate from Template infrastructure tests, but give both categories the same required validation gate.

## 1. Template version and provenance

The repository has no canonical Template version today. It has sample release and milestone versions, MCP server identity, dependency pins, and storage format versions; none is the Template's installed revision.

Proposed Template release metadata is published upstream with **release tag, source commit SHA, release notes, compatibility implications, and a manifest of Template-owned paths**. Consumer repositories record:

```toml
[template]
upstream = "Kooraseru/Template"
release = "template/v1.0.0"
revision = "<full immutable upstream commit SHA>"
```

The above is an **illustrative record**; do not copy it as a real installed release or claim that v1.0.0 exists. Until the first Template release, report only an upstream revision and mark the published version as unavailable. A consumer may adopt only some Template-owned paths; path ownership must therefore be explicit, not inferred from a shared repository name.

A read-only check should compare the recorded release or SHA against official upstream releases, classify changes by owned path and manifest capabilities, and report `current`, `update-available`, `diverged`, `unverifiable`, or `unknown-origin`. Notifications are **advisory**, not an automatic Build failure. Don't use GitHub fork ancestry: template-created repositories do not share normal fork history. Never overwrite user-owned files or automatically merge upstream revisions. A future update assistant may prepare a reviewable patch or PR, including detected local modifications, but must not apply it silently.

## 2. Dependency policy

`dependencies/dependencies.json` selects releases and providers; `dependencies/dependencies.lock` resolves the exact assets, fingerprints and cryptographic digests. Keep both in sync and fail closed on stale or unsupported locks. No `latest` or automatic nightly promotion in normal CI. Rebuild/update locks in a dedicated dependency-update PR and validate each supported host.

**Lute compatibility experiment in this PR:** use official stable `v1.0.0` with upstream release asset SHA-256 values for all currently declared platforms. The previous baseline is `v1.0.1-nightly.20261104`; the release is older and may lack APIs used by modern rule validators or packaging. A green Node-only test is insufficient; hosted `Build`, `Tests`, `validate`, and `Code Review`, plus a local `act` run, are required before accepting the pin. If any features are missing, restore the exact nightly pin and document the blocking API instead of adding a silent fallback to `latest`.

Do not conflate external tool releases, Node runtime versions, Docker images, GitHub Actions references, MCP protocol dates, or upstream API dates with a Template version.

## 3. Contract policy

Keep ordinary component contracts versionless and validate required fields, types, capability relationships and trust boundaries. For **durable serialized formats** (dependency lock, local execution records, signed/hashed artifact manifests), document each supported positive integer format version and either reject or explicitly migrate old structures. For example, `dependencies.lock` currently uses 2; artifact manifests use 1; local CI records write 2 and currently read 1 and 2.

Revise `rules/general/standards/structural-compatibility.md` to clarify this narrow exception when implementing the proposal. No SemVer inside storage records, no opportunistic migration of signed evidence, and no dispatch on version fields where structural and capability validation suffices.

## 4. CI ownership – preserve the intended declarative architecture

The **precise historical pivot** was commit `6f6254d` (Nov 11), `Replace delegated CI entry with fixed Build, Test, Validate, and isolated Publish stages`. The previous architecture at `aa96c635` used `Resolve` and `Bootstrap` before generating an execution graph from `ci/components/**/component.toml` and `.github/config/credentials.json`.

The present workflow directly hardcodes `publish-general`, `publish-projects`, `publish-rulesets`, `publication-result`, credential environment names, `CI_TOKEN` and App secret expressions. Adding an entirely new privileged capability now requires editing YAML, which violates the intended contract. **This should be refactored rather than preserved as the public extension API.**

Proposed division of authority:

- **Authored launcher:** stable triggers, read-only Build/tests/required `validate` check, a minimal and explicitly trusted publication bootstrap, and fixed access to only one bootstrap credential transport if necessary. Ordinary component and credential additions do not edit the launcher.
- **Component planner:** discovers `ci/components/**/component.toml`, validates phase, trust boundary, dependencies and outputs, and produces a signed/verified immutable job plan.
- **Credential catalog:** `.github/config/credentials.json` owns roles, source names, permission requirements and environment bindings. The scheduler computes the least-privileged job-level permissions and selects matching environments; secrets are never sourced from arbitrary PR code. No `toJSON(secrets)` blanket transport.
- **Generated privileged jobs:** use the existing `ci/github/workflows/workflow.luau` and `ci/github/resources/branches/branchRun.luau` machinery where appropriate. Give each job only its declared roles and credential environment, propagate outputs with provenance checks, and retain ref/commit-safe cleanup. An isolated bootstrap GitHub App or trusted OIDC broker may be required: GitHub evaluates job permissions and environment secret bindings *before execution*. A JSON catalog cannot magically grant a new permission to an existing job.
- **Result reporting:** a stable gate must describe the **actual completed** Build and publication tasks. Optional missing capabilities can skip with declared policy; unexpected job-admission errors fail with actionable diagnostics. No fabricated success, silent privilege escalation, or background automatic retries.

Keep what was actually verified: the fixed Build/Tests/validate path passed on PR #40 and on the subsequent `source` push. The older delegated workflow passed PR validation at least once (run `43140087728`), but that run **did not exercise privileged generated publication**. Reusing its code is not proof of hosted source-push correctness.

**Current failure to solve before implementing this migration:** source-push run `43163094094` passed Build/Tests/validate and general publication; the `ci-projects`, `ci-rulesets`, and `ci-reporting` jobs failed with zero steps. Those jobs uniquely reference protected environments with `deployment: false`. GitHub documents a specific admission failure for custom deployment protection rules combined with `deployment: false`; this is a **plausible cause, not confirmed from the available job logs**. Check environment protection annotations/settings rather than disabling protections without review.

A restoration should be developed on **one work branch**, proven in an unprivileged PR and in an opt-in, disposable environment. Never use the next `source` merge as the first privileged integration test.

## 5. Universal and consumer-owned feature tests

Retain colocated Template infrastructure tests (`ci/**`, `dependencies/packages/**`) but report them as `universal`. Define a supported `tests/features/<feature>/` extension point for downstream projects; optionally `tests/universal/` for truly generic project-level invariants. A structured test manifest should declare runner, command, working directory, capabilities, isolation and output protocol. The current `ci/test.sh` is not yet that registry.

The single required gate aggregates universal and feature suite results and **fails if either category fails**. PR-authored tests run without publishing secrets, with bounded timeouts, and publish distinct result groups. CLI, GitHub Actions and editor/MCP should all consume the same structured results. Feature tests must not require editing `ci/test.sh` or a central `.gitignore`.

## 6. Rollout and acceptance

1. **Phase A (this PR):** proposal, historical audit, and Lute stable compatibility trial. No privileged CI workflow changes and no automatic Template update service.
2. **Phase B:** add provenance/ownership metadata and advisory comparison against tagged upstream Template releases. Versioning remains independent of project releases.
3. **Phase C:** install a single declarative test registration interface with separate universal/feature reporting, backed by headless tests.
4. **Phase D:** reduce authored YAML to stable bootstrap/validation, using existing generated job and credential catalog machinery with end-to-end publication tests. Fix environment-admission handling and maintain hard permission separation; clean up obsolete generated-mode code only after parity.
5. **Phase E:** surface Template advisory update status and structured tests in the editor host. No protocol-specific minimum version without evidence a capability check is insufficient.

**Merge criteria for Phase D:** unchanged launcher when a new component/credential role is added; required `validate` reflects actual execution; fork PR has no privileged credentials; both environment and OIDC paths are tested; missing optional credentials produce configured skip outcomes; artifact provenance and release policies remain intact; clean source-push publication in a disposable repo; local `act` remains usable.

Nothing here grants permission to run real publication or to merge into `source`.