# Luau instance construction

Declare populated instance fields separately before attaching a metatable. The validator flags a nonempty table of named fields passed directly to the global setmetatable with a locally owned table as the metatable. It highlights the field table.

Empty tables used for staged construction, dynamic metatables, and mixed table entries fall outside this check. See [object construction](../../../../rules-old/languages/luau/structures/oop/objects.md) and the [fixture matrix](tests/TEST_MATRIX.md).

A colon declaration warns when its receiver is a locally declared table used as an instance metatable. A dot declaration on the same kind of table warns on a first parameter named `self` without a type annotation. Reassigned bindings, colon calls, and methods on externally owned tables stay outside the receiver check.

The validator also warns on an explicit __index link between two distinct local classes. Both tables must be demonstrably used as instance metatables. A plain lookup table's default values and an instance's link to its own class do not meet that condition.


## Inheritance

Avoid inheritance by default. Prefer composition or an explicit structural interface. The check allows other named fields in the metatable and leaves duplicate or computed keys for review because they can replace the explicit link.
