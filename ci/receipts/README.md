# Build receipts

PR events run cheap checks using the protected base controller. They inspect
proposed Git objects and configuration without executing proposed controller
scripts with reporting credentials. Missing admin validation leaves the gate
unsatisfied. Expensive hosted execution requires an explicit admin request.
Only admins may have repository write access; contributors use forks. This
boundary is checked before hosted execution. Admins merge through the receipt
merge command: a green check by itself is not acceptance.

## Identity and defaults

Receipts identify repository, PR head/base, tested commit, Git tree, SHA-256
source manifest, controller/build fingerprints, targets, execution platform,
results, logs, and package checksums. Source and controller hashes use committed
Git blobs, including modes, rather than platform-specific working-tree bytes.
Dirty or uncommitted input is rejected. Submodules require future explicit input
support and are currently rejected.

| Option | Default | Meaning |
| --- | --- | --- |
| Target `reuse_identity` | `exact_commit` | Require the exact built commit. |
| Target `reuse_identity = "source_tree"` | Explicit opt-in | Permit another SHA only with the same complete source tree and inputs. |
| Target `reproducible` | `false` | When true, contributor/admin output checksum differences block acceptance. |
| Receipt retention | 30 days | Expired staging is rejected; subsequent submissions clean expired dedicated drafts. |
| Signing keys | Empty list | Local admin signatures require enrollment through a protected source PR. |
| Hosted fallback | Disabled | Missing results wait for an admin request. |
| Local target selection | Linux only | Native Windows/macOS require hosted validation; never inferred from act emulation. |

Compiler profiles are opt-in; the template baseline has no compiler workload.
The 32 catalogue entries explicitly opt into tree reuse because they
only run static compiler probes. When adding project commands, audit this
declaration for every target. Use exact-commit identity if Git SHA, describe,
history, branch names, or commit-derived versions influence output.
Original tested SHAs remain in reused provenance. Release metadata separately
identifies the selected release SHA; it does not pretend another commit ran.
Image recipes and pinned base identities enter fingerprints; the actual image
archive hash and package/probe record are bound into execution evidence.
The resolved fingerprint additionally binds actual image identity, native
platform, Node version, and toolchain probe hashes. A contributor/admin resolved
environment mismatch blocks comparison until those environments are aligned.

## Contributor claims

Run the actual workflow with act/GitHub Local Actions and collect its artifacts.
Contributor receipts are claims, not required-check authority. Submit the JSON
receipt on the PR, or use `claim-submit` outside act with an existing GitHub CLI
login. An admin can pass that JSON to their independent validation request.
Missing native coverage is explicit; the admin completes those targets.

```powershell
node ci/receipts/cli.mjs claim-context 17
act workflow_dispatch --eventpath build/tmp/receipts/event.json --artifact-server-path build/cache/act-artifacts/claims --container-architecture linux/amd64
node ci/receipts/cli.mjs collect-act build/cache/act-artifacts/claims/1 build/receipts/claim
node ci/receipts/cli.mjs claim-submit build/receipts/claim/receipt.json
```

Use a fresh artifact-server directory for each run. The collector requires its
plan to match the clean controller checkout. `CI_LOCAL_TARGETS` may select a JSON
array of Linux target names for partial local coverage; do not edit tracked CI
configuration to select targets. act runner mappings remain as configured in
`.actrc` or the GitHub Local Actions extension.

## Independent admin validation

For hosted validation, run from a trusted clean source controller checkout:

```powershell
node ci/receipts/cli.mjs request 17
# Optional independent comparison:
# node ci/receipts/cli.mjs request 17 build/receipts/claim/receipt.json
```

Hosted validation reuses already accepted targets and executes missing ones.
The reporting job has the automatic token; build jobs do not have check-write,
publication, or signing permissions. Acceptance is bound to the completed admin
dispatch and its original `validation-receipt` artifact, not an arbitrary run ID.

For local admin validation, stay on the trusted source controller, fetch the PR
objects without checking out proposed controller code, then run act:

```powershell
node ci/receipts/cli.mjs local-context 17
act workflow_dispatch --eventpath build/tmp/receipts/event.json --artifact-server-path build/cache/act-artifacts/admin --container-architecture linux/amd64
node ci/receipts/cli.mjs collect-act build/cache/act-artifacts/admin/1 build/receipts/admin
```

This produces only executed Linux targets. Collect, sign, and stage outside act:

```powershell
# One-time key creation; choose a new private-key path outside the repository:
# node ci/receipts/cli.mjs keygen C:/Users/USER/AppData/Local/TemplateCI/admin.pem
# Enroll the printed PUBLIC record in keys.json through an admin source PR.
node ci/receipts/cli.mjs sign build/receipts/admin/receipt.json ENROLLED_KEY_ID C:/Users/USER/AppData/Local/TemplateCI/admin.pem
node ci/receipts/cli.mjs submit build/receipts/admin/receipt.json
node ci/receipts/cli.mjs request 17
```

An optional final argument to `sign` supplies contributor receipt JSON for
comparison. Keys stay outside build environments. Windows key creation removes
inherited file access; Unix keys use mode 0600. No private key or PAT belongs in
the template. Key records include admin login and revocation state; current
repository admin permission is checked whenever a result is accepted.

Staging uses unique `ci-validation-<UUID>` draft releases. Both receipt and
archive uploads are downloaded and verified before acceptance. They are not
stable/beta/canary releases. Local act never stages or officially publishes.
Claim/input/result mismatches block acceptance. Non-reproducible checksum
differences are reported; publication always uses admin-validated output.

## Merge and release

```powershell
node ci/receipts/cli.mjs merge 17
```

The command regenerates the expected plan from trusted controller code,
requires the current source base to be an ancestor of the PR head, verifies all
targets and staging assets, checks head/base freshness again, then performs a
normal protected merge with an exact-head guard. It does not use admin bypass.
An admin can still circumvent policy or change repository protection; trust in
admins and their machines is deliberate. Receipts do not cryptographically
prove physical execution against a dishonest trusted operator.

The source push first resolves accepted artifacts. It restores matching outputs
without compiler execution or image rebuilding, rechecks cheap validation,
assembles releases, and revalidates acceptance before publication. Missing,
expired, revoked, altered, or incomplete artifacts block publication. Request
source validation with `request 0`, then rerun the blocked source-push workflow
after its accepted staging is available. Existing channel releases remain intact.

## First installation

The old source controller cannot validate a receipt protocol it does not contain.
For the first activation PR only, an admin may explicitly request:

```powershell
node ci/receipts/cli.mjs request 17 --bootstrap
```

This runs the exact same-repository activation PR head, with all required targets.
Its base must provably predate this contract. The run artifact binds the original
receipt and the current admin identity. Bootstrap cannot be requested for a
later base that already contains the contract. Bootstrap local preview uses
`local-context 17 build/tmp/receipts/event.json --bootstrap`; this does not grant
new local keys trust before their protected-source enrollment.

References: https://docs.github.com/en/rest/checks/runs and
https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/troubleshooting-rules

Draft releases are visible only with repository write access. The trusted validation
job retrieves and verifies accepted bundles, then transfers distributions and logs
as named workflow artifacts. Build jobs remain read-only and recheck distribution
provenance before reuse. They do not need draft-release access.
