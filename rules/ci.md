# CI rules

## Boundaries

Keep one workflow at `.github/workflows/ci.yml`. GitHub Actions supplies static runner stages and permission boundaries; **Luau/Lune** owns component discovery, contract inspection, scheduling, invocation, and reconciliation in `ci/bootstrap/`. The bootloader is trusted coordination, not a catalogue of application tasks. Do not use Python in CI, including tests. Do not introduce smoke-test scaffolding; verify actual discovery and execution behavior instead.

Discover actual tasks exclusively from `ci/components/` using the patterns in [discovery](discovery.md). Do not create hypothetical components, fixtures in the tracked component directory, or placeholder preflight implementations just to produce a green run. Preflight belongs to the same discoverable component system, not a hardcoded workflow task.

## Contracts

Before execution, inspect a **leading `ci-contract` TOML comment** in each matched Luau component, without requiring or evaluating it. This is source-local metadata, not a separate manifest. The recognized fields are `provides`, `requires`, `inputs`, `outputs`, `events`, `runtime`, `boundary`, and `enabled`. All top-level values must appear before a `[runtime]` table header. For example:

```luau
-- ci/components/example.luau
--!strict
--[[ci-contract
provides = ["example.ready"]
requires = []
inputs = ["source/**/*.luau"]
outputs = []

[runtime]
os = "linux"
architecture = "x64"
end-ci-contract]]

return function(context)
    print(context.event)
end
```

Validate field types, identifiers, known runtime shapes, permissions, ambiguous names, dependency cycles, missing and duplicate providers, and conflicting output ownership. `inputs` and `outputs` use repository-relative glob patterns; never treat an input match as permission to import or execute it.

A contract declares capabilities, not an index of known platforms. `runtime.os` and `runtime.architecture` describe the execution environment required by that discovered task. Any failure to prove a trust boundary or runner relationship should produce a diagnostic instead of silently skipping work.

## Planning and execution

Validation capabilities run during planning on a fixed read-only runner. Non-validation tasks require a discovered and applicable `validation.preflight` provider. Plan only the selected event and dependency closure. Keep dependent worker tasks in the same runner/boundary execution group, ordered by dependencies; reject unsupported cross-runner or cross-permission dependencies explicitly.

The planner projects discovered groups into a GitHub matrix, respecting the 256-entry limit by batching only compatible independent groups. A missing group result, blocked task, incomplete output, or failed stage is a CI failure, not a hidden skip. A green empty-template run proves only the bootloader path; real components require their own runtime verification.

Privileged work is separately gated by a manually dispatched trusted source branch, required environment approval, and explicit GitHub permissions. Do not self-grant permissions in a component contract or bypass provenance checks. Source checkout and downloaded plans must agree before tasks run. Keep credentials, generated artifacts, and local CI state out of Git.

## Validation before promotion

Validate the actual Luau bootloader and the live GitHub workflow. Verify static rejection cases and real dynamically discovered worker execution before calling the implementation fully validated. Report what was actually run, what was skipped, and any unavailable platform or permission coverage. Do not commit smoke-test scripts as substitutes for real components.
