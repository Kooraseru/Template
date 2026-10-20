# Trusted build receipts

This contract governs trusted evidence, not ordinary development test eligibility.

## Approval and identity

Automatic hosted PR execution performs cheap checks. Expensive hosted execution
requires administrator authorization or matching accepted builds. Contributor
claims never authorize merging or publication.
Fork contributions remain untrusted.

Accepted receipts require committed clean inputs. Identity binds repository,
current PR head/base, tested commit, Git tree, canonical SHA-256 source manifest,
controller/build inputs, execution platform, target outcomes, logs, and artifact
checksums. Preserve canonical fingerprint bytes across implementation changes.

## Signing and acceptance

Local administrator signatures use enrolled public keys from protected source;
private keys remain outside execution environments. Hosted acceptance binds an
administrator source-controller dispatch to its original completed-run artifact.
Recheck administrator permission, key revocation, age, and bundle contents on reuse.

First installation permits explicit administrator bootstrap of the exact activation
PR only when its base predates this contract.

Independent validation compares shared contributor targets and rejects changed
inputs/results. Missing target evidence requires administrator execution.
Reproducible targets reject checksum differences; other differences are recorded.
Administrator output is authoritative. Trusted administrators and machines remain
a trust boundary; a checksum alone does not prove execution.

## Reuse and publication evidence

Targets default to exact-commit reuse. Explicit source-tree reuse permits commit
changes only when the complete tree and declared build inputs match. Retain the
original tested commit separately from the selected release commit. Template smoke
probes opt in; Git-derived build information requires exact commits.

Native target evidence cannot be replaced by emulated execution. Privileged signing
may transform a validated unsigned artifact, followed by verification.

Dedicated internal draft releases transport accepted bundles for 30 days. Source
files do not store receipts. Missing or expired acceptance waits for administrator
validation, with no automatic expensive fallback.

Public packages require verified matching accepted receipts and rechecked packages.
Administrator merging uses the freshly verified receipt merge command; a green
check alone is not acceptance.
