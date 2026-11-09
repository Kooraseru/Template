# Nested conditional expressions

Warn when a Luau conditional expression uses another conditional directly as its condition or a branch value, including through parentheses. A flat elseif chain remains readable and passes. Decisions nested inside separate calls are left for review.

See [expression guidance](../expressions.md) and the [fixture matrix](tests/TEST_MATRIX.md).
