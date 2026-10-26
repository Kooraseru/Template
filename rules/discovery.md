# Discovery and module shape

## Globs, not inventories

**Use glob patterns for file discovery and referencing.** A consumer defines a structural pattern and validates matches; it must not maintain a table of discovered component names or separate file indices. A glob describes eligible shapes, not which particular components must exist.

CI components have two equivalent direct-child patterns:

- `ci/components/*.luau` (single-module component)
- `ci/components/*/init.luau` (multi-module component head)

A matched name is the component identity. The same name in both forms is an error. Directory internals are private unless their parent explicitly declares another extension point. Invalid direct children are **errors**, not silently skipped, with the sole exception of the initial empty-tree `.gitkeep` marker.

The trusted glob adapter may use Lune's filesystem API internally to expand patterns. Callers must use glob discovery, not reproduce the traversal or track filenames themselves. `*` matches one path segment; `**` spans zero or more segments. Glob expansion must be deterministic; reject symlinks in discovered CI scopes and unsafe path traversal.

## Luau module boundaries

Prefer `name.luau` for one cohesive module. Promote to `name/init.luau` only when the directory has meaningful internal implementation and the head owns a public contract, coordination, validation, or lifecycle. Do not create forwarding-only `init.luau` files.

For Lune, `init.luau` represents its **containing directory**. To require a private module inside that same directory, use `require("@self/child")`; `require("./child")` resolves outside the directory module. Non-`init.luau` files use ordinary relative imports. Changing a module into a directory head therefore requires checking its imports.

Each Luau file uses a path comment and `--!strict`; follow global naming, control-flow, types, and module shape rules. Use Lune for host-side Luau tasks. Do not introduce Python, JavaScript, or shell scripting as a replacement CI coordinator. Native GitHub Actions infrastructure and minimal YAML shell command invocation are permitted; Node.js should not be an application-level dependency.

## No inferred inventory

`source/hosts/` owns host implementations and their capabilities; `plugins/` owns application plugins. Adding a conforming child must not require edits to its owning parent, workflow, dispatch table, or platform matrix. Do not infer target combinations from a global platform list.
