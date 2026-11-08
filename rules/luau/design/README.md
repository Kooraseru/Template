# Luau Structure System

A Luau file chooses a structure before applying structure-specific rules.

Language-wide rules still apply, but each structure decides which elements are required, optional, or intentionally absent.

The structure is chosen by why the file exists, not by which syntax looks familiar.

| Why the file exists | Structure |
| --- | --- |
| Transform inputs into one result without owned state | functional return-function module |
| Group related operations behind one named module surface | procedural table module |
| Manage independent instances with identity, lifetime, or owned resources | OOP object |
| Expose declarative values that callers read as data | external data source and typed loader |
| Own startup wiring, boundary normalization, or subsystem facade behavior | entry point |
| Describe data attached to entities without per-instance methods | ECS component |
| Iterate over queried entities and apply behavior from their data | ECS system |

Do not add ceremony from another structure unless the current file earns it.

If a file feels awkward, check the "why" before changing syntax. A table module with one function may want to become a return-function module. A data-only table may belong in JSON/TOML with a typed loader. A procedural module that manufactures independent lifetimes may want to become OOP.

## Structure references

- [Return-function modules](function-modules/README.md) and [composition](function-modules/composition.md)
- [Procedural modules](procedural/README.md), [table modules](procedural/table-modules.md), and [shared state](procedural/stateful-modules.md)
- [Objects](objects/README.md) and [structural interfaces](objects/interfaces.md)
- [Declarative data boundaries](declarative-data/boundaries.md)
- [Entry points](../files/entry-points.md)
- [ECS design sketches](ecs/README.md)
