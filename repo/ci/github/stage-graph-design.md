# Proposed stage graph design

This is the next design, not a claim that the current components have already
been split into dozens of native jobs.

## Shape

A component owns a discoverable stage tree. A meaningful leaf stage has a source
path, contract, input/output patterns, capability requirements, credential roles,
and failure policy. Adding a valid stage folder adds work without modifying a
workflow or a central stage inventory. Current components become UI groups and
aggregate outcomes; their successful siblings cannot conceal failed/skipped work.

Flatten the discovered stages into the existing Luau scheduler's task contract.
Keep one dependency planner, executor, output verifier, and reporting vocabulary.
There is no global list of mandatory phases and no target/platform cross-product.
For example, build stages expand from actual `source/hosts/*/` definitions, not an
inventory of Windows/Linux/macOS combinations.

Native job IDs derive from validated stage paths, with collision checks; display
names retain the readable path. Stage granularity follows independent work and
useful failure boundaries, not a target of exactly 98 jobs or one job per line.

## Execution and fallbacks

| Situation | Required behavior |
| --- | --- |
| Feature supported and configured | Run it and verify its real output/effect. |
| Feature disabled/no applicable inputs | Mark skipped with a reason. |
| Missing App/PAT/permission/plan | Warn with exact configured credential names and mark that feature unavailable/skipped. |
| Best-effort external service fails | Record failed (non-blocking), continue independent stages. |
| Required stage fails | Block only its dependents; still finish independent stages. |
| Expected artifact missing/corrupt | Fail the producer/consumer contract; never claim success. |
| Lockfile invalid/untrusted | Stop unsafe action execution; never fall back to unlocked dependencies. |

Capabilities are established by actual access/probes, not by guessing that all
private repositories lack a feature. Attestations attempt GitHub's appropriate
backend; private Free/Pro/Team unavailability must not crash builds/publications.
No private artifacts are redirected to a public signing service as a fallback.

## Native Actions boundary

GitHub still cannot invent arbitrary native jobs or needs edges within an existing
run. The App/token bootstrap renders the complete discovered graph and lockfile
on the temporary execution branch before that run starts. Without credentials,
the same graph runs in the Luau fallback with per-stage logs and outcome reporting.
Do not promise native visualization in fallback mode or generate source commits.

Optional native adapters own platform-only steps such as attestations. Credential
roles and permissions belong to their stage contract. Split the existing large
components incrementally, retaining output compatibility and meaningful real-run
verification before replacing their current contracts.

## Current management work

- Lockfile: generated with GitHub's official pinned CLI, including generated
  execution workflows; runner enforcement remains a hard security boundary.
- Attestations: best-effort, separately reported from artifact preparation and
  release publication. Only successful signing is called attested.
- Projects: App/PAT apply path, explicit credential warnings/skips.
- Labels: the source catalog is the complete allowed repository label set.
- Caches, runner provisioning, and additional deployment targets remain separate
  future features. Existing Pages deployment remains operational. No placeholder
  settings pretend to configure GitHub usage/performance reporting pages.
