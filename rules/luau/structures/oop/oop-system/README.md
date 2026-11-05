# OOP System

OOP rules apply to metatable-backed objects with independently constructed
instances.

This template leans toward OOP objects for stateful runtime structures. When a
concept owns identity, mutable state, a lifecycle, or resources, model it as an
object with a clear constructor and instance methods. Keep plain data,
stateless operations, startup wiring, and ECS roles in their matching
structures; OOP is a strong default for stateful structures, not a wrapper for
every module.

Use OOP when a value has identity, lifetime, owned resources, or instance
methods that operate on stored fields.

The point is to make ownership explicit. An object says: this value owns state
or resources over time, and methods operate on that particular instance.

Use this when the useful question is:

```text
Which instance owns this state or resource?
```

Do not use OOP for one pure operation, static grouped functions, plain data, ECS
components, or startup wiring.

## Dynamic Module Composition

Prefer composing extensible structures from modules discovered at their owning
directory. Derive names and require paths from the discovered file or directory
shape instead of maintaining a second hardcoded list of implementations.
Validate discovered names, entry points, and required contracts before use.

Dynamic requiring is appropriate at declared extension points and composition
boundaries. Keep ordinary dependencies explicit with normal `require` calls;
do not turn routine module dependencies into string-based lookup. Do not load
untrusted candidates just to inspect them, and keep discovery deterministic.
