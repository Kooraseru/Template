# Const bindings

An initialized module-level local with one binding and one initializer can use `const` when the binding is never reassigned. This informational finding includes imports and values read by nested functions. Direct and compound assignments count as writes, including writes in closures. A write to a shadowing local does not affect the outer binding.

A const binding can still reference a mutable table. Updating its fields does not reassign the binding. Directly returned module table literals, locals inside functions or control-flow blocks, multiple bindings, and uninitialized declarations stay outside the check.
