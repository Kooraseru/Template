# Luau file conventions

Hand-written Luau source declares strict mode at the top. The validator accepts the directive on line one or directly after a path header. The separate path-header rule checks the header itself. A conflicting first-line directive is highlighted in full.

Generated code and fixture inputs are outside the production scan. See [file layout](../../../../rules-old/languages/luau/files/file-system.md) and the [fixture matrix](tests/TEST_MATRIX.md).

Standalone `--# <name>` section markers use this rule's `sectionMarkers` settings in [rules.json](../../../../.vscode/config/rules.json). Explicitly disallowed and unlisted names warn. Inline comment lookalikes, strings, and block documentation are ignored. Update the marker lists for this rule when choosing to allow or disallow a marker.

Use role headers when they improve scanning. A small file can omit them. Repeating the same approved standalone marker at the same indentation with only whitespace between copies produces a warning on the later copy. Repeated names separated by code or another comment stay outside this check.
