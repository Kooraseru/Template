# Build validation contract

One workflow owns local act and hosted execution. Automatic PR runs perform
cheap checks; expensive validation requires an explicit admin request.
Contributors may submit claims, but claims never authorize merging or releases.
Only admins hold repository write access. Fork contributions are untrusted.

Receipt identity binds repository, current PR head/base, tested source commit,
Git tree, canonical SHA-256 source manifest, controller/build inputs, execution
platform, target outcomes, logs, and artifact checksums. Committed clean inputs
are mandatory. Missing native evidence cannot be replaced by act emulation.

Local admin receipt signatures use enrolled public keys from protected source;
private keys stay outside execution environments. Hosted acceptance is bound to
an admin source-controller dispatch and the original completed-run receipt
artifact. Recheck current admin permission, revocation, age, and assets on reuse.
First installation permits an explicit admin bootstrap run of the exact
activation PR only when its base predates the contract.

Every target defaults to exact-commit reuse. Explicit source-tree declarations
permit SHA changes only when the complete tree and declared build inputs match.
Retain the original tested SHA; selected release SHA is a separate identity.
Template smoke probes explicitly opt in. Projects using Git-derived build
information must require exact commits.

Independent validation compares shared contributor targets and rejects changed
inputs/results. Missing target evidence requires admin execution. Reproducible
targets reject checksum differences; other differences are recorded. Admin
output is authoritative. Trusted admins/machines remain an explicit trust
boundary; SHA-256 alone does not prove execution.

Dedicated draft releases transport accepted bundles for 30 days. Channels and
source files do not store receipts. Missing or expired acceptance waits for
admin validation, with no automatic expensive fallback. Official publication
uses the automatic token and rechecks accepted packages. Local act never
publishes. Admin merging must use the freshly verified receipt merge command;
a green check alone is not acceptance.
