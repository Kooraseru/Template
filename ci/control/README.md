# Manual CI control panel

The single `.github/workflows/ci.yml` workflow serves automatic checks, local
execution and hosted administrator operations. The hosted manual form is restricted
to repository administrators. It contains twelve dropdowns and no receipt JSON or
PR-number text field.

| Group | Setting | Choices |
| --- | --- | --- |
| Run | Operation | Validate, Build, Publish, Full Run |
| Run | Pull request | Source and generated open PR choices |
| Validate | Scope | All, Configuration, Workflow rules, Access policy, Receipts, Release tooling |
| Build | Targets | Configured, All supported, Linux, Windows, macOS, individual catalogue targets |
| Build | Compiler filter | Any, GCC, Clang, MSVC, MinGW, Rust |
| Build | Architecture filter | Any, x64, ARM64 |
| Build | Container images | Configured, Skip, Required by selected builds, All catalogue images |
| Outputs | Repository | Configured, Skip, Generate only, Generate and publish |
| Outputs | Documentation | Configured, Skip, Generate only, Generate and publish |
| Outputs | Releases | Configured, Skip, Assemble only, Publish configured channels, Publish canary, Publish beta, Publish stable |
| Policy | Cache | Reuse matching results, Rebuild outputs, Rebuild images and outputs, Require stored results |
| Policy | Gates | Enforce all, Ignore validation failures, Ignore incomplete coverage, Ignore both |

`options.json` defines the form contract. Workflow validation verifies its twelve
controls against the YAML. The build-target dropdown additionally includes the
32 entries from `ci/build/targets.json`.

## Stages and operations

Jobs use stage prefixes in their display names: Maintenance, Validate, Build,
Evidence and Publish. Validation suites also use GitHub's `::group::` log commands
for collapsible sections. GitHub Actions does not have a job-label or nested stage
property; the prefixes organize its native flat job list. The `gate` job retains
its exact name because repository branch protection requires that status check.

- Validate authorizes and plans the request, runs the selected checks, and stores
  `validation-evidence` plus the release plan as workflow artifacts.
- Build also builds or restores selected distributions, generates enabled outputs,
  assembles enabled release previews, and stages receipts and bundles. It never
  publishes official repository, documentation or channel outputs.
- Publish requires matching stored distributions for every selected target. It
  restores and verifies them, generates publication outputs and publishes enabled
  destinations. It never falls back to compiling missing targets.
- Full Run performs validation, build, evidence staging, assembly and publication.
  Its publication jobs can verify evidence staged by the same in-progress run;
  other consumers must wait for that run to finish successfully.

Use `source` in GitHub's existing workflow-ref picker. A selected PR identifies
the tested head, independently of the trusted source controller. The server
rechecks that the PR is open and targets this repository's source branch. Stale
titles do not change PR identity. PRs support Validate and Build; publication
operations require Source. First-install activation remains a receipt CLI operation
using the exact eligible activation PR checkout and `request NUMBER --bootstrap`.

## Source execution approval

A hosted push to source by a verified repository administrator authorizes missing
builds to execute. CI queries the commit's associated pull requests and records an
exact matching administrator merge as `admin-merge`, including PR and merger.
A direct administrator push is recorded separately as `admin-source-push`; it is
not described as a reviewed PR. Local events, other branches and non-admin actors
cannot grant this authority. The run summary explains which authority was found.

Approval permits execution, not fabricated success. Matching accepted outputs are
still reused when available; missing outputs are built and verified in this run.
The Evidence stage stores receipts for authorized source pushes as well as manual
runs. Publication verifies those receipts and still enforces source protection,
artifact integrity and commit freshness.

## Selection and cache behavior

Configured preserves each source snapshot's repository settings. Other selections
are applied in memory, including when planning pinned release commits. Target,
compiler and architecture filters intersect. Empty intersections and missing
required image definitions fail before building. Configured images automatically
include dependencies when explicitly selecting catalogue build targets; Skip is
invalid if selected builds require images. Explicit release channels must already
exist in `ci/releases/channels.toml`.

Operation bounds publication. Choosing Generate and publish while running Build
still generates only. Publish with either rebuild policy is rejected; use Full Run.
Rebuild outputs ignores accepted distributions but can reuse image archives.
Rebuild images and outputs also skips image-cache restoration. Require stored
results fails if matching staged distributions are unavailable.

Accepted distributions, execution logs and provenance remain in verified staging
bundles with the receipt retention policy. Recipe-keyed image archives use Actions
cache. Diagnostic runs also stage their results, but may reuse diagnostic receipts
only with matching validation scope, target filters and gate policy. They cannot
provide official PR acceptance or publication evidence. Successful target checksums,
platform evidence and source identity are verified on restoration.

Gate policy separates selected validation failures from missing receipt coverage.
It does not suppress authorization/planning failures, failed builds, failed enabled
output jobs, checksum mismatches, source freshness checks, repository protections
or GitHub permission checks. Narrow validation scopes, build filters and bypassed
gates are recorded as diagnostic evidence, rather than silently certifying full
configured coverage. Receipt JSON comparison remains in the receipt tooling.

## Refreshing pull request choices

`refresh-prs.mjs` updates only the marked generated choice block in the workflow.
The Maintenance job runs on source pushes, PR open/update/rename/close events and
an hourly reconciliation schedule. It uses trusted source code, paginates open
source PRs, quotes titles, neutralizes workflow expressions, and guards updates
with the current workflow blob SHA. Changes use a `[skip ci]` commit message.

GitHub does not populate a live PR dropdown itself. Updating a workflow file may
require an additional credential and must satisfy source branch protection.
The maintenance job tries `GITHUB_TOKEN`; an optional `CI_WORKFLOW_TOKEN` repository
secret can supply a narrowly scoped credential permitted to update workflow files.
The workflow does not create credentials or change branch protection. If the update
is denied, the job reports the permission problem and the existing choices remain.

Administrators can refresh locally using an existing GitHub CLI login:

```powershell
node ci/control/refresh-prs.mjs
git add .github/workflows/ci.yml
git commit -m "Refresh CI pull request choices"
```

Generated choice updates are real source commits and can invalidate commit-bound
validation evidence. Automatic refresh is maintenance, not proof of source validation.

References:
https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
https://docs.github.com/en/actions/reference/workflow-commands-for-github-actions
https://docs.github.com/en/actions/how-tos/monitor-workflows/use-the-visualization-graph
