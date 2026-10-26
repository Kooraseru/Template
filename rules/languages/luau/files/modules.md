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
