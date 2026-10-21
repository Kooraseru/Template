# ECS as a data-processing architecture

Choose ECS when **many entities share reusable sets of component data** and behavior is best expressed as systems querying those components.

ECS is not synonymous with OOP, and a few ordinary objects do not justify an entity scheduler. The choice should be driven by query patterns, cardinality, and data ownership.

- Components express data, not miniature class hierarchies.
- Systems express transformations over selected component sets.
- Resources represent system-wide state with explicit ownership.
- Schedule and dependency ordering must be intentional.
- Do not assume component presence from a previous query unless the framework guarantees it.
- Keep external effects at well-defined boundaries.

Use the idioms of the actual selected ECS library (if any); this repository template does not prescribe an ECS crate.

Read [components](components.md) and [systems](systems.md). If the problem concerns a handful of independently owned lifetimes, [objects](../oop/objects.md) are often simpler.

[Example processing kernel](examples/integrate.rs) illustrates the structure without adding a mandatory application or CI smoke test.
