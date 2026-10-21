# Selecting a Rust structure

Choose the structure because of the **problem's responsibility**, not because Rust supports a syntax or a framework makes it fashionable.

| What the code must own | Preferred structure |
| --- | --- |
| Immutable or validated values, records, and alternatives | [Data](data/data-system.md) |
| Stateless transformation or composition | [Functional](functional/functional-system.md) |
| Operations coordinated around a shared resource, service, or workflow | [Procedural](procedural/procedural-system.md) |
| Independent instances with identity, invariants, and lifecycle | [OOP-like owned objects](oop/oop-system.md) |
| Component data processed by reusable systems over entities | [ECS](ecs/ecs-system.md) |
| Task lifetimes, synchronization, and message passing | [Concurrency](concurrency/concurrency-system.md) |
| Bridging C APIs, native handles, or foreign memory layouts | [FFI](ffi/ffi-system.md) |

These families are not exclusive language modes. A concurrent application can contain data records, pure functions, and stateful objects.

## Decide by the missing ingredient

- A function with no retained state does not need a `struct` just to give its method a name.
- An ordinary `struct` is not automatically OOP. A record is data; an object manages identity or invariants.
- A `trait` expresses a contract. It is not necessarily inheritance, dependency injection, or an OOP hierarchy.
- An ECS should earn the cost of its component and query infrastructure; a few objects do not require one.
- A single `async` call does not justify a new scheduler or shared mutable registry.
- A C-compatible struct is a boundary representation, not proof that it is safe to dereference foreign pointers.

Favor useful boundaries over evenly sized directories. Don't create every family in an application by default; use only what it needs.

Language-wide [good writing](../language/writing.md) and [guard-first control flow](../language/control-flow.md) apply to every family. Each structure file adds requirements and exclusions for that particular role.
