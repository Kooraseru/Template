# Luau Modules

Modules should expose the shape that matches their responsibility.

Do not wrap a single operation in an identity table just to make every file look
the same.

Common module shapes:

- return-function module
- table module
- metatable-backed object
- data/config module
- entry point
- ECS component or system

The structure docs own the whole-file expectations for each shape.

## Requiring and Composition

Use explicit `require` calls for stable dependencies between known modules.
Use dynamic requiring when a parent owns an extension point whose eligible
children are added, removed, or renamed independently. Discover children from
that directory, derive their identities from their paths, validate their
shape, then require them in a deterministic order. Do not duplicate the child
inventory in a registry or dispatch table.

Keep discovery and loading separate when candidates cross a trust boundary:
validate paths and metadata before executing module code. Follow the owning
runtime's supported require-path convention; do not assume all Luau runtimes
resolve paths identically.


# Luau directory module roots

A directory may expose one public module surface when it hides meaningful internal implementation.

- `init.luau` is the preferred modular directory head when the resolver supports directory imports (including Lune and common Rojo workflows).
- `index.luau` is permitted only when the project deliberately uses an explicit resolver convention. Do not assume every Luau runtime resolves a directory import to `index.luau`.
- Keep a standalone `name.luau` file until there are real internal modules or coordination that justify `name/init.luau`.
- Never create an empty or forwarding-only directory head merely to standardize appearance.

Keep imported directory heads side-effect-free except for explicitly declared lifecycle behavior; expose a coherent contract. Executable entry points remain explicit, and importing a module should not unintentionally launch an application, build, or CI operation.

When adopting a directory root, check import resolution in the actual target runtime rather than assuming Roblox, Lune, and custom loaders have identical behavior.


# Entry Points

Entry points own startup or boundary wiring.

They may coordinate other modules, connect to engine/plugin lifecycle, validate
environment assumptions, and call into project-owned surfaces.

Entry points should not become dumping grounds for implementation behavior that
belongs in a structure-specific module.
