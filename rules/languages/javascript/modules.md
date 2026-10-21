# JavaScript modules and state

Prefer an ES module with explicit imports and exports when the build and browser
environment support it. A legacy global facade is an adapter for an existing
page, not a reason to place unrelated behavior in one file. Do not create a
directory index that merely reexports every child; a subsystem head should own
validation, lifecycle, coordination, or a stable facade.

Keep pure transformations separate from DOM reads and writes. A module-scoped
state object is appropriate when there is one shared controller for one domain;
its initialization, cleanup, and re-render paths must be clear. Use instances
when multiple independent copies must coexist. Avoid duplicate mutable copies
of values derivable from the source model.

Treat configuration and content as inputs with one owner. Do not hardcode the
same locale, theme, project, or asset list in both build code and browser code.
Validate external records once at their entry boundary, then use a stable
internal shape. Name functions for effects and outcomes, not vague stages.

An entry point wires modules, listeners, and startup order. It should not hide
the implementation of every feature. Event listeners attached during render
must not accumulate across re-renders; choose delegation or explicit cleanup.

