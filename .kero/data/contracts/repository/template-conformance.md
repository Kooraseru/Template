# Template conformance

Template conformance is optional external maintenance, independent of the CI
orchestrator and its promotion gate. Its sole hosted entry point is
`.github/workflows/template.yml`. Deleting that file opts out without changing
build, receipt, signing or publication authority. Do not add this check to `gate`
or branch protection automatically.

## Authority and compatibility

The workflow retrieves `Kooraseru/Template` at `source` on each run. The retrieved
commit owns the checker and contract; its exact SHA is recorded in the assessment.
Compatibility comes from actual required structures, relationships and permission
boundaries, never a template version, schema revision or equal file checksums.
A newer upstream commit alone is not drift.

The executable contract is `validation/ruleset.json.template`. It selects existing
workflow rules, configuration validation and Luau module policy from their owners;
it does not copy their constraints. Downstream copies of those rules do not
control an upstream assessment.

## Inspection and ownership

Check tracked infrastructure responsibilities, required CI stages and publication
boundaries, referenced local actions, module structure, source ownership of build
settings, repository ownership of publication settings and disposable build output.
Authored directories belong to the existing architecture. Hidden tooling metadata
is permitted. Application source under `src/`, its language, dependencies, native
manifests and configured commands may differ between projects.

The checker reads the downstream checkout as data. It never requires downstream
modules, invokes build commands, installs project dependencies or runs their tests.
Consumed files must be tracked regular files, not symlinks or submodule entries.
The read-only token and separate upstream checkout cannot grant publication rights.
There are no publication environments, signing secrets or artifact reuse privileges.

Static declarations and module policy are inspected, not proven runtime behavior.
An unchanged public interface with a broken implementation still needs ordinary CI.
Template drift reports do not constitute a security certification.

## Scheduling and results

Run on pull requests, source pushes, manual dispatch and a weekly schedule. The
schedule detects upstream changes even when a consuming repository is inactive.
GitHub schedules run from the repository's default branch and may be delayed:
https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows

Use a read-only `pull_request` check, not privileged `pull_request_target` execution.
Upstream tools are executed; downstream executable content is not.

Results are `conforms`, `drift_detected` or `unable_to_assess`. Findings include the
path and failed expectation. The workflow stores JSON, emits annotations and writes
a summary. Drift fails only the independent check. Failed retrieval, inaccessible
files or checker execution cannot silently report success; initialization preserves
an unavailable assessment if execution never completes.

The workflow file itself is copied integration. Consumers must permit its checkout
and artifact actions and access to the public upstream repository. Upstream checker
and rule updates are automatic; changes to the copied workflow adapter can still
require a deliberate update. This is not an auto-updater and creates no issues or PRs.

## Using and removing

Copy `.github/workflows/template.yml` to a consuming repository. No local checker,
manifest, secret, GitHub App or numerical compatibility marker is required to run
that workflow. Keep it on the default branch for scheduled assessments.

For conversion, run an initial assessment, address ownership and interface findings,
then run the application's actual CI. Do not manufacture template directories or
empty language folders merely to silence diagnostics. Preserve application behavior
and use appropriate platform coverage before promotion.

To opt out, remove the workflow. The checker and its development tests in this
Template repository remain ordinary template infrastructure; their presence does
not make conformance a downstream promotion gate.
