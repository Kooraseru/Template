# Dynamic discovery

Prefer structural discovery over hand-maintained inventories for extensible rule, plugin, and component systems. A discoverable component should carry its own contract; adding a conforming child should not require editing an unrelated central list.

## Rule discovery

Discover executable rule directories with a `README.md` and a `validation.luau` file or `validation/init.luau` directory head. A language-native validation entrypoint is permitted where required by the owning language. Grouping directories are not executable rules. Do not treat `tests/`, generated files, or examples as production source.

For a validated rule, `tests/valid/`, `tests/invalid/`, and `tests/review/` contain named independent fixtures; `tests/TEST_MATRIX.md` describes their expected results. The test system discovers and executes these separately. Production validators never import, invoke, or scan those fixtures.

Choose rules by the source language, file purpose, and documented applicability. Do not load all rules into every prompt merely because the tree can be enumerated. Resolve overlaps by the most specific applicable contract, then report unresolved ambiguity rather than enforcing both interpretations.

## Deterministic boundaries

- Use explicit path patterns for eligible components; do not invent missing component names from a platform list.
- Normalize paths before comparison and reject path traversal and case-ambiguous identities.
- Decide symlink policy deliberately and do not cross a trust boundary through an unexpected symlink.
- Sort discovery results for deterministic execution and diagnostics.
- Keep checker failure, rule violation, and absence of applicable rules as distinct outcomes.

The scanner may use a filesystem API internally. Consumers should depend on the scanner's contract rather than reimplementing discovery in each agent or Preflight adapter.

## Lune module boundary

For Lune, `init.luau` represents its containing directory. To require a private sibling from inside that directory, use `require("@self/child")`; a relative import can resolve differently from an ordinary file module. Recheck imports when converting between a single file and a directory module.
