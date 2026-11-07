# Checker contract

Rules are the specification; checkers are optional, testable implementations.

Each validated rule owns a `README.md`, `tests/`, and either `validation.luau` for a single implementation or `validation/init.luau` for several cooperating implementations. The owning runtime may use a language-native extension. An unvalidated rule stays a single `.md` file. Each validator must declare its language, source scope, diagnostic location, limitations, and exclusions.

Preflight may discover validators dynamically, but discovery does not make an unreviewed validator authoritative. Validation is applied to the project's source files, not to its fixture directory. A separate test system runs named valid, invalid, and review cases, using `tests/TEST_MATRIX.md` as the acceptance contract. Prefer syntax-tree or semantic analysis to regular expressions when the requirement depends on code structure, binding identity, mutation, or control flow.

Do not infer a violation from capitalization, formatting, file size, or other unrelated proxies. A checker should report what it can prove from the input. When it cannot determine intent or cross-module behavior, avoid a fabricated certainty; narrow the check or report a clearly identified advisory finding.

The integration contract distinguishes a rule violation from a checker failure. One semantic finding should not be emitted twice by different adapters merely because both Preflight and the underlying tool observed it. Intentionally invalid fixtures are test inputs, not routine workspace diagnostics.

Before merging changes to checker logic, record which cases were exercised, which remain unsupported, and which command or integration path produced the result.
