# Blank-line separation

The validator warns when two consecutive multi-line statements at module scope touch with no blank line between them. A comment between the statements counts as a visual separator. Single-line statements may remain grouped.

This check is advisory and emits warnings. It does not reformat files. Nested statement lists are not checked yet; see the review fixture and matrix.

See [Luau blank-line guidance](../../../../rules-old/languages/luau/language/blank-lines.md) and the [fixture matrix](tests/TEST_MATRIX.md).
