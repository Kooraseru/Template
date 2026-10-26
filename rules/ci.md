# CI rules

## One workflow, one entry point

The only workflow is `.github/workflows/ci.yml`. Its **single job** is named `Starting bootstrap`; it checks out the repository, installs pinned Lune through the existing composite setup action, then invokes `ci/bootstrap/init.luau`. The workflow must not maintain stages, matrices, component lists, or plans of work. All component-specific orchestration stays in the bootloader.

Bootstrap owns discovery, static validation, dependency ordering, execution, and reporting. Discover actual work using [the owning glob shapes](discovery.md) under `ci/components/`; never add hypothetical components or manually maintained dispatch tables. Preflight is a discoverable component, not a hardcoded workflow stage.

**GitHub limitation:** a running job cannot materialize new native GitHub Actions jobs or switch runners or permissions within the same run. The single-job bootstrap invokes its CI components on the actual runner; it must **reject** privileged work requiring unavailable permissions. Host-specific builds requiring other runners cannot be represented as native jobs in this single-job workflow and must not be reported as executed. Reintroducing native multi-runner or privileged execution would require an explicitly approved GitHub-workflow architecture change.

## Component contracts

Contracts live in a leading static `ci-contract` TOML comment on each component's `.luau` entry. The trusted discoverer reads but never requires implementation code to inspect it. All top-level fields precede the `[runtime]` table:

```luau
-- ci/components/example.luau
--!strict
--[[ci-contract
provides = ["example.ready"]
requires = []
inputs = ["source/**/*.luau"]
outputs = []

end-ci-contract]]

return function(context)
	print(context.event)
end
```

The `Component` object owns the contract shape and its validation. `identity` and `entry` derive from the filesystem and may not be supplied by TOML. Supported keys are the constructor's validated fields. **Host implementations and their OS/architecture identities belong exclusively to `source/hosts/`**. CI must not maintain a platform inventory or duplicate host identity in component contracts. Components can select source files through input globs. Fields describe capabilities, not permission grants. Keep contract compatibility versionless and reject unknown structures instead of inferring behavior.

The bootloader rejects malformed candidates, duplicate identities/providers, missing requirements, cycles, unsupported events, and conflicting output globs before executing discovered work. The `inputs` and `outputs` declarations are repo-relative glob patterns, not an instruction to execute matched files. The preflight component will eventually own input-sensitive static analysis; do not invent that implementation merely to populate the template.

## Execution and security

Planning-time validators execute first, on the actual runner, and cannot depend on worker components. Worker execution requires an enabled and event-applicable discovered `validation.preflight` provider. All selected components must respect read-only workflow permissions. The CI runner is not an inventory of supported application hosts.

Once contracts and the dependency graph are validated, each component implementation runs in its own Lune child process. Its declared outputs must exist before it counts as passed; blocked/failed work results in a failed bootstrap. The bootstrap reports actual outcomes to the Actions job log and step summary. Do not bypass code provenance or give downloaded or discovered metadata higher trust than the checkout.

## Source formats and verification

Repository-owned CI uses **YAML, TOML, and Luau**. Python and Node.js are not CI implementation languages; GitHub's built-in actions may use their own runtime. Minimal shell commands to install and invoke Lune are permitted. Do not create smoke tests, test scripts, artificial components, or a `tests/` tree.

Use the real workflow's output as evidence. A completed empty-template run demonstrates only its discovery/bootstrapping path; it does not validate real component execution or other platforms. Document uncovered runtime/permission cases without inventing or skipping work.
