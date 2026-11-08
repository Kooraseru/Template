# Guard-first branches

The validator flags a two-branch statement when the successful branch consists of calls or assignments and the fallback is only a bare `return`, `continue`, or `break`. Moving the operations after the guard keeps local declarations in their original scope. The rule offers a diagnostic for manual review.

The validator also flags a direct `pcall(assert, ...)` using both global built-ins. A direct assertion for an invariant passes. Shadowed functions and protected callbacks with their own logic require review.

Boolean conditionals also warn when a comparison is wrapped in `then true else false`, or when `then false else true` can be expressed with `not`. Positive truthiness conversions require review.

See the [fixture matrix](tests/TEST_MATRIX.md).
