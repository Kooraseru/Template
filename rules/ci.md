# CI rules

## One workflow, one entry point

`.github/workflows/ci.yml` owns one bootstrap job. It installs pinned Lune and
invokes the `ci/main.luau` launcher. The workflow does not maintain component
lists, dependency plans, matrices, or build logic. The bootstrap discovers
components from `ci/components/`, reads their static contracts, orders them by
declared capability dependencies, invokes them, and reports their outcomes.

The template currently has one CI component: `ci/components/build/`. Every
component is a directory with `init.luau` as its public head. Keep implementation
modules beside the head and private unless the component explicitly exposes a
child extension point. Do not create root-level component `.luau` files.

`config/luau/.luaurc` defines `@ci` as the `ci/` root and `@workspace` as the
repository root. The Luau language server loads it through the workspace's
`baseLuaurc` setting. Lune resolves runtime `.luaurc` files by walking upward
from each script, so CI modules use file-relative imports unless a root config
is deliberately introduced. Use `@self` for private siblings within a
component package.

## Component class contract

Each `init.luau` defines and returns a pure `Component` class. Its typed static
`Component.Contract` field declares capabilities, requirements, input and
output globs, supported events, execution boundary, and enabled state. The
directory name supplies identity. The bootstrap loads class definitions,
validates `Component.Contract`, and plans dependencies without constructing
component instances.

The class exposes `Component.new()` and instance methods such as
`Component.Run(self, context)`. The constructor initializes owned collaborators
and all instance fields. Private classes and helpers live in sibling modules.
The invoker checks the exported class shape, constructs one instance per child
process, then calls its `Run` method.

```luau
local Builder = require("@self/Builder")

local Component = {}
Component.__index = Component

type ComponentContract = {
	provides: { string },
	requires: { string },
	inputs: { string },
	outputs: { string },
	events: { string },
	boundary: string,
	enabled: boolean,
}

local contract: ComponentContract = {
	provides = { "build.completed" },
	requires = {},
	inputs = { "source/main.c", "source/hosts/*/init.luau" },
	outputs = { "build/*.exe" },
	events = { "push", "pull_request", "workflow_dispatch" },
	boundary = "read",
	enabled = true,
}
Component.Contract = contract

type ComponentFields = { builder: Builder.Builder }
export type Component = setmetatable<ComponentFields, typeof(Component)>

function Component.new(): Component
	local fields: ComponentFields = { builder = Builder.new() }
	return setmetatable(fields, Component)
end

function Component.Run(self: Component, context: { event: string }): ()
	self.builder:Run(context)
end

return Component
```

The `provides` and `requires` fields express capability dependencies, not
permission grants. A component must not declare privileged work unless the
workflow architecture separately authorizes it. Host implementations and
platform identities belong under `source/hosts/`; the build component discovers
them there instead of repeating their names.

## Bootstrap module and execution

`ci/bootstrap/init.luau` is a ModuleScript-style class module. It only defines
`Bootstrap.new()`, `Bootstrap.Run(self)`, and returns `Bootstrap`. The launcher
owns process startup, environment checks, and error-to-exit handling. Bootstrap
delegates discovery, planning, execution, and reporting to collaborator classes.
Keep Markdown summaries and other authored text in text files such as
`ci/bootstrap/summary.md`; reporter classes supply runtime values and write the
rendered artifact.

Component class modules must be side-effect-free at module scope because the
bootstrap requires each class to inspect its typed static contract. Constructors
and `Run` methods remain untouched until the planned task starts in its own
process. Reject malformed contracts, duplicate identities or providers, missing
capabilities, dependency cycles, unsupported events, conflicting output globs,
and unsafe filesystem entries. Components run in one dependency-ordered list
after planning succeeds.

Each implementation runs in a fresh Lune child process so module cache and
global state do not leak across components. Declared outputs must exist before
a component counts as passed. Failed or blocked dependencies fail the run.
Discovered code must come from the checked-out repository; do not execute
downloaded or otherwise untrusted components.

## Source formats and verification

Repository-owned CI uses YAML, TOML, and Luau. Python and Node.js are not CI
implementation languages. Minimal shell commands to install and invoke Lune
are permitted. Do not add smoke-test projects, artificial components, test
scripts, or a `tests/` tree to the template.

Use real workflow output as evidence. A completed empty-template run proves
only its discovery and bootstrap path; do not claim coverage for components or
platforms that did not execute.
