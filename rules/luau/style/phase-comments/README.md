# Phase comments

An advisory finding appears at the first unexplained transition in a function with at least 20 distinct lines that start executable statements. The check looks for a loop, substantial conditional, or scoped block spanning at least five lines beside other work in the function body. It evaluates nested functions separately.

Count statement starts so wrapped expressions, large literals, blank lines, and comment lines cannot push a short function over the threshold. A standalone prose comment immediately before the next phase, at the same indentation, covers that transition. Directives, path headers, annotation-only comments, and section markers do not count. The check recognizes prose placement and leaves its meaning to review.

See [comment guidance](../../../../rules-old/languages/comments.md) and the [fixture matrix](tests/TEST_MATRIX.md).
