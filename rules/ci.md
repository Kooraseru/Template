# CI rules

## One workflow, one entry point

`.github/workflows/ci.yml` owns one bootstrap job. It installs pinned Lune and
invokes the executable `ci/entry.luau` launcher. The workflow does not maintain component
lists, dependency plans, matrices, or build logic. The bootstrap discovers
components from `ci/components/`, reads their TOML manifests, orders them by
declared capability dependencies, invokes them, and reports their outcomes.

The template has separate `build` and `pages` components. `build` compiles
sources through discovered hosts. `pages` turns authored `docs/` content into
the static site artifact under `build/pages/`. Keep these responsibilities in
their respective component packages.

Every component is a directory with `component.toml` for declarative metadata
and `init.luau` as its public Luau class head. Keep implementation modules beside
the head and private unless the component explicitly exposes a child extension
point. Name implementation files in camelCase. Do not create root-level
component `.luau` files.

`.luaurc` defines `@ci` as the `ci/` root and `@workspace` as the
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
`siteBuilder.luau`. These stages produce `build/pages/`; the hosting workflow
consumes that artifact separately. Do not put Pages rendering in the source
build component.

## Bootstrap module and execution

`ci/bootstrap/init.luau` is a ModuleScript-style class module. It only defines
`Bootstrap.new()`, `Bootstrap.Run(self)`, and returns `Bootstrap`. The launcher
owns process startup, environment checks, and error-to-exit handling. Bootstrap
delegates discovery, planning, execution, and reporting to collaborator classes.
Keep Markdown summaries and other authored text in text files such as
`ci/bootstrap/summary.md`; reporter classes supply runtime values and write the
rendered artifact.

Discovery parses `component.toml` as data and does not execute component code.
Component modules load only in their planned child process. Reject malformed
manifests, duplicate identities or providers, missing capabilities, dependency
cycles, unsupported events, conflicting output globs, and unsafe filesystem
entries. Components run in one dependency-ordered list after planning succeeds.

Keep page rendering, static asset copying, site assembly, and external hosting
as separate responsibilities. The `pages` component produces `build/pages/`;
deploying that artifact requires a separately authorized publication workflow.

Each implementation runs in a fresh Lune child process so module cache and
global state do not leak across components. Declared outputs must exist before
a component counts as passed. Failed or blocked dependencies fail the run.
Discovered code must come from the checked-out repository; do not execute
downloaded or otherwise untrusted components.

## Preflight reachability

`ci/preflight/` analyzes the plan produced by the existing component discovery
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
