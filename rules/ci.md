# CI rules

Repository support lives under `repo/`; see `repo/README.md` for ownership rules.
Keep feature-specific settings beside their content or CI implementation.
Shared settings live in `repo/config/`. Preflight provider implementations and
their configuration are discovered together under `repo/ci/preflight/providers/`.

## One workflow, one entry point

`.github/workflows/ci.yml` owns one bootstrap job. It installs pinned Lune and
invokes the executable `repo/ci/entry.luau` launcher. The workflow also carries the approved native Pages upload/deploy adapter, with enablement and paths resolved by Luau. It does not maintain component
lists, dependency plans, matrices, or build logic. The bootstrap discovers
components from `repo/ci/components/`, reads their TOML manifests, orders them by
declared capability dependencies, invokes them, and reports their outcomes.

`repo/config/github.toml` owns GitHub repository paths, user-defined aliases,
credential-name mappings, and optional branch bootstrap. `repo/ci/github/` may render
the scheduler's validated tasks as native jobs and dependency links when an
explicitly configured App/token can push workflow files. Generated workflows
exist only on run branches. They are not an additional maintained component
inventory. Without usable credentials the existing local scheduler runs the plan.
Credentials are stored in GitHub; configuration contains secret/variable names
only. Never embed actual tokens or private keys in code or TOML.

CI setup belongs in `repo/ci/dependencies/`. Lune's pin, checksums, and bootstrap script
are colocated under `repo/ci/dependencies/lune/`. GitHub Packages declarations are kept separately in
`repo/content/packages/packages.toml`. Keep CI tooling/configuration out of application
`source/` so source globs do not distribute the pipeline itself.

The template has separate `build` and `pages` components. `build` compiles
sources through discovered hosts. `pages` turns authored `repo/content/docs/` content into
the static site artifact under `build/repo/pages/`. Keep these responsibilities in
their respective component packages.

Every component is a directory with `component.toml` for declarative metadata
and `init.luau` as its public Luau class head. Keep implementation modules beside
the head and private unless the component explicitly exposes a child extension
point. Name implementation files in camelCase. Do not create root-level
component `.luau` files.

`.luaurc` defines `@ci` as the `repo/ci/` root and `@workspace` as the
repository root. The Luau language server loads it through the workspace's
`baseLuaurc` setting. Lune resolves runtime `.luaurc` files by walking upward
from each script, so the root aliases are available to nested CI modules.
Use @self from a component head to load its direct collaborators; use `./sibling` for imports between private implementation
files. For dynamic module discovery, keep fixed path prefixes in named `const`
bindings and interpolate only the discovered identity. Lune API definitions
come from the pinned runtime's `lune setup` output.

## Component manifest and class

Each `component.toml` declares capabilities, requirements, input and output
globs, supported events, execution boundary, and enabled state. The directory
name supplies identity. Bootstrap validates these fields centrally and plans
dependencies without loading implementation modules. Do not repeat this
metadata in Luau or add per-component validators.

The class exposes `Component.new()` and instance methods such as
`Component.Run(self, context)`. The constructor initializes owned collaborators
and all instance fields. Private classes and helpers live in sibling modules.
The invoker checks the exported class shape, constructs one instance per child
process, then calls its `Run` method.

```toml
provides = ["build.completed"]
requires = []
inputs = ["source/main.c", "source/hosts/*/init.luau"]
outputs = ["build/*.exe"]
events = ["push", "pull_request", "workflow_dispatch"]
boundary = "read"
enabled = true
```

```luau
local HostBuilder = require("@self/hostBuilder")

local Component = {}
Component.__index = Component

type ComponentFields = { hostBuilder: HostBuilder.HostBuilder }
export type Component = setmetatable<ComponentFields, typeof(Component)>

function Component.new(): Component
	local fields: ComponentFields = { hostBuilder = HostBuilder.new() }
	return setmetatable(fields, Component)
end

function Component.Run(self: Component, _context: { event: string }): ()
	self.hostBuilder:Run()
end

return Component
```

The `provides` and `requires` fields express capability dependencies, not
permission grants. A component must not declare privileged work unless the
workflow architecture separately authorizes it. Host implementations and
platform identities belong under `source/hosts/`; the build component discovers
them there instead of repeating their names.

The `pages` package keeps Markdown conversion in `markdownRenderer.luau`,
static file copying in `staticAssetCopier.luau`, and output-tree assembly in
`siteBuilder.luau`. These stages produce `build/repo/pages/`; the hosting workflow
consumes that artifact separately. Do not put Pages rendering in the source
build component.

## Bootstrap module and execution

`repo/ci/bootstrap/init.luau` is a ModuleScript-style class module. It only defines
`Bootstrap.new()`, `Bootstrap.Run(self)`, and returns `Bootstrap`. The launcher
owns process startup, environment checks, and error-to-exit handling. Bootstrap
delegates discovery, planning, execution, and reporting to collaborator classes.
Keep Markdown summaries and other authored text under `repo/content/ci/`, such as
`repo/content/ci/bootstrap-summary.md`; reporter classes supply runtime values and write the
rendered artifact.

CI guides and design documents belong under `repo/content/docs/ci/`.
Keep executable pipeline code under `repo/ci/`; do not store authored Markdown there.

Discovery parses `component.toml` as data and does not execute component code.
Component modules load only in their planned child process. Reject malformed
manifests, duplicate identities or providers, missing capabilities, dependency
cycles, unsupported events, conflicting output globs, and unsafe filesystem
entries. Local execution runs components in one dependency-ordered list after
planning succeeds. Optional native execution uses that same task plan and its
dependency edges.

Keep page rendering, static asset copying, site assembly, and external hosting
as separate responsibilities. The `pages` component produces `build/repo/pages/`;
deploying that artifact is handled by the publication component and the native Pages adapter, using the run-provided token and environment protections.

Each implementation runs in a fresh Lune child process so module cache and
global state do not leak across components. Declared outputs must exist before
a component counts as passed. Failed or blocked dependencies fail the run.
Discovered code must come from the checked-out repository; do not execute
downloaded or otherwise untrusted components.

## Preflight reachability

`repo/ci/preflight/` analyzes the plan produced by the existing component discovery
and planner. It does not define per-component validators or repeat component
contracts. The same analyzer runs before CI execution and through the live VS Code
task, which publishes file diagnostics to the Problems panel. A module reference
that cannot be resolved is an error; dynamic behavior the analyzer cannot prove is
reported as unknown and does not claim runtime success.

## Source formats and verification

Repository-owned CI uses YAML, TOML, and Luau. Python and Node.js are not CI
implementation languages. Minimal shell commands to install and invoke Lune
are permitted. Do not add smoke-test projects, artificial components, test
scripts, or a `tests/` tree to the template.

Use real workflow output as evidence. A completed empty-template run proves
only its discovery and bootstrap path; do not claim coverage for components or
platforms that did not execute.

## Package records and publication conflicts

`repo/content/packages/packages.toml` owns shared GitHub Packages policy, not a
package inventory. Discover direct folders under `repo/content/packages/records/`.
Each folder owns `package.toml` and `README.md`; its name supplies identity.
Malformed present records are errors. Compilation fixtures omit registry
metadata and are never treated as registry-ready packages.

Both `packages.on_existing` and `release.on_existing` accept `skip`, `fail`, and
`replace`, defaulting to `replace`. Keep one shared policy contract. Publishers
must enforce destination capabilities and protection rules, and must not silently
fall back or delete/recreate an immutable publication. Package registry adapters
remain separate from compilation and staging.

Preflight may recognize a generated input from the declared outputs of a planned
dependency before files exist. This is a projection of the scheduler's contract;
execution must still check that the producer actually created its outputs.

A component that performs no work returns `"skipped"` from `Run`; normal
completion returns nil. The isolated invoker transports skip with its reserved
exit code, and both scheduler summaries and native execution reports preserve
that outcome. Skipped publication must not be labeled passed. Consumers of a
skipped producer are blocked rather than reading nonexistent artifacts.
Publication follows enabled manifests and configured records automatically;
unset GitHub override variables are not an additional opt-in gate.

Release downloads are owned by `release.assets` globs in releases.toml, not
GitHub Packages records. Release staging depends on compilation and carries
validated files and hashes to the publisher. New releases with assets stay drafts
until uploads succeed; mutable replacement verifies a new upload before removing
the old asset. Missing configured outputs or mismatched build provenance fail.

## Contribution templates and labels

GitHub-native issue forms and PR templates are authored directly in `.github/`
on the default branch. Do not duplicate them under repository content or add
another workflow for them. `repo/config/labels.toml` owns the label definitions;
`sync-labels` validates form references and creates/updates labels using the
built-in token with Issues write permission. The catalog is authoritative: remove all unlisted repository labels. Keep IDs and issue/PR associations for labels still declared. Already matching label data reports skipped.

## Management and capability fallbacks

Source configuration is authoritative for labels: remove every remote label not
in repo/config/labels.toml after validating/upserting all declared entries. Do not
carry exemptions for labels added by defaults or other automation.

Project blueprints are discovered under repo/config/projects/*/. Source owns
managed project structure; actual issue/PR records remain GitHub data. Projects
use configured App/PAT roles and warn/skip on unavailable account permissions.
Do not confuse missing credentials with an unsupported integration.

Optional integrations must be isolated. Attestations are best-effort and record
failed/non-blocking versus skipped versus successful signing accurately. Private
repository capabilities depend on account entitlement; probe/attempt them rather
than blanket-rejecting private repositories. Independent work must continue.
Lockfile failures must never downgrade to unlocked action execution.
