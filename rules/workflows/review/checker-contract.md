# Checker contract

Rules are the specification; checkers are optional, testable implementations.

Each validated rule owns a `README.md`, `tests/`, and either `validation.luau` for a single implementation or `validation/init.luau` for several cooperating implementations. The owning runtime may use a language-native extension. An unvalidated rule stays a single `.md` file. Each validator must declare its language, source scope, diagnostic location, limitations, and exclusions.

Template's Rules check discovers validators dynamically. It applies the same discovered set to workspace source and to each rule's own valid, invalid, and review cases. Use `tests/TEST_MATRIX.md` as the fixture acceptance contract. Prefer syntax-tree or semantic analysis to regular expressions when the requirement depends on code structure, binding identity, mutation, or control flow.

Do not infer a violation from capitalization, formatting, file size, or other unrelated proxies. A checker should report what it can prove from the input. When it cannot determine intent or cross-module behavior, avoid a fabricated certainty; narrow the check or report a clearly identified advisory finding.

The integration distinguishes a rule violation, an expected fixture finding, and a checker failure. Expected findings appear under **Rule fixture** on the input file. Unexpected fixture outcomes and checker failures affect Rules status. Preflight reports compilation results separately.

Before merging changes to checker logic, record which cases were exercised, which remain unsupported, and which command or integration path produced the result.

Path-sensitive fixtures should encode their input context in their directory and file names. The runner preserves directory fixture paths under a virtual `source/` root and checks each `.luau` file in the tree with that path. Findings still point to the actual fixture files in Problems. Do not add sidecar `context.json` path overrides.

Rule-specific options belong under `ruleSettings` in `.vscode/config/rules.json`, keyed by the rule's full path under `rules/`. The JSON Schema accepts rule paths dynamically and leaves each settings object open; the owning rule documents and validates its own fields.
