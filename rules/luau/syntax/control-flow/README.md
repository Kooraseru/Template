# Guard-first branches

The validator flags a two-branch statement when the successful branch consists of calls or assignments and the fallback is only a bare `return`, `return nil`, `continue`, `break`, or a call to the global `error` built-in. Moving the operations after the guard keeps local declarations in their original scope. The rule offers a diagnostic for manual review.

The validator also flags a direct `pcall(assert, ...)` using both global built-ins. A direct assertion for an invariant passes. Shadowed functions and protected callbacks with their own logic require review.

Boolean conditionals also warn when a comparison is wrapped in `then true else false`, or when `then false else true` can be expressed with `not`. Positive truthiness conversions require review.

See the [fixture matrix](tests/TEST_MATRIX.md).

Use a boolean expression directly when both branches just repeat its result. This includes parenthesized comparisons, explicit negation, and short-circuit expressions whose operands both produce booleans. Use not when the branches only negate a condition. A positive conversion around a short-circuit expression that can yield another type stays for review.

Use a guard when handling an absent or invalid precondition keeps the main path flat. Keep branches whose negation would make the decision harder to read.
