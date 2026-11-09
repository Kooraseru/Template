# Checker contract

Rules are the specification; checkers are optional, testable implementations.

Each validated rule owns a `README.md`, `tests/`, and either `validation.luau` for a single implementation or `validation/init.luau` for several cooperating implementations. The owning runtime may use a language-native extension. An unvalidated rule stays a single `.md` file. Each validator must declare its language, source scope, diagnostic location, limitations, and exclusions.

Template's Rules check discovers validators dynamically. It applies the discovered set to workspace source and runs each fixture through its owning validator. Use `tests/TEST_MATRIX.md` as the fixture acceptance contract. Prefer syntax-tree or semantic analysis to regular expressions when the requirement depends on code structure, binding identity, mutation, or control flow.

Do not infer a violation from capitalization, formatting, file size, or other unrelated proxies. A checker should report what it can prove from the input. When it cannot determine intent or cross-module behavior, avoid a fabricated certainty; narrow the check or report a clearly identified advisory finding.

The integration distinguishes a rule violation, an expected fixture finding, and a checker failure. Expected findings appear under **Rule fixture** on the input file. Unexpected fixture outcomes and checker failures affect Rules status. Preflight reports compilation results separately.

Before merging changes to checker logic, record which cases were exercised, which remain unsupported, and which command or integration path produced the result.

Path-sensitive fixtures should encode their input context in their directory and file names. The runner preserves directory fixture paths under a virtual `source/` root and checks each `.luau` file in the tree with that path. Findings still point to the actual fixture files in Problems. Do not add sidecar `context.json` path overrides.

Configure rules under the rules map in [rules.json](../../../../.vscode/config/rules.json). Each key is a discovered rule ID, such as luau/file-system, or a path to that rule folder. Rule folders declare custom options in a sibling settings.json containing JSON Schema. The editor and runner read those declarations directly.

Workspace defaults apply first, then the rule entry, then matching source overrides in list order. The last matching override that provides severity or settings wins for that field. Each scoped settings object replaces the whole settings object. Fixtures use the base settings and fixtureSeverity. The error, warning, info, and off levels control finding display. Fixture failures and checker crashes still fail Rules.

A validator without custom settings exports a rule with Check. A configurable validator exports Create(settings), which receives the policy values and returns a rule with Check. Create can reject invalid combinations of settings. The runner initializes the base and each scoped settings variant before checking sources.
