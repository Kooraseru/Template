# Blank-line separation

The validator warns at crowded statement boundaries, including inside functions, loops, and branches. A run is crowded when it has two unseparated boundaries around loops, substantial conditionals, scoped blocks, or named functions that span at least five lines. Two such blocks touching also warn on their own. A blank line or standalone comment between statements separates the run.

Keep related single-line statements, consecutive early guards, and a short exit after a block together when they read naturally. The check also covers adjacent multiline statements at module scope. It emits warnings and leaves edits to the author.

See the [fixture matrix](tests/TEST_MATRIX.md).
