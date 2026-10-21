# Source updates and promotion

Administrators may push directly to `source` using their configured branch bypass.
The push needs no prior CI approval. Source is editable development authority, not
a claim that every revision has passed validation.

Every recognized source push runs the full configured post-push audit, validation,
test, build, and evidence pipeline. Administrator authority permits execution and
successful downstream publication; it does not fabricate passing results. Do not
reduce validation scope, ignore failing gates, or treat missing required coverage
as success merely because the actor is an administrator.

Record whether a source update came from a validated administrator PR merge or a
direct administrator push. The merge path can reuse matching accepted PR evidence
under the existing receipt policy. Direct pushes require the same applicable checks
and matching evidence; absence of a PR is not an authorization failure.

Successful validation makes the revision eligible for automatic promotion under
the existing acceptance and publication policy. Do not require a second approval
solely because the update was a direct push. Unrecognized or unauthorized updates
must not receive promotion authority.

Failure blocks promotion to generated `main`, documentation deployment, and public
releases. It must not roll back, remove, or otherwise undo the administrator's
source changes. Development on source remains available for the next correction.

Existing protected publication permissions and credentials remain authoritative.
Mutable source workflow code is not independent proof of its own trustworthiness;
metadata cannot expand protected authority. Do not introduce a new approval system
for sensitive changes unless an existing explicit security contract requires it.
