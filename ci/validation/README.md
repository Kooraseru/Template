# Declarative checks

Define validation constraints in data files and test inputs with their expected
results in `*.cases.json`. Luau scripts load those definitions and execute the
checks; adding a case should not require adding a Luau assertion or callback.

`config.rules.json` defines the CI configuration constraints. Its rule paths use
dot-separated fields, numeric array positions, and `*` to visit collection items.
`$` selects the root value.

Supported constraints include types, dense arrays, enumerations, equality,
minimum lengths, uniqueness, prefixes, forbidden values, and string patterns.
Patterns use **Luau string patterns**, not regular expressions. Conditional
rules use `when.path` with `equals` or `contains`. Shared definitions may be
referenced with `use`; additional rejected patterns extend inherited constraints.

Test cases specify a name, expected validity, and a patch over the baseline.
Patch keys are dot-separated field paths. Cases may remove top-level fields
with `remove`. Operation-specific executors handle setup, execution, and result
comparison.

Publication eligibility lives in `ci/access/publication.rules.json`.
Workflow structure and gate expectations live in `workflows.rules.json` and
`gate.rules.json`. Filesystem checks live in `repository.checks.json`.
Build fixtures use `*.fixture.json` for files, commands, expected exit codes,
and optional expected output. Use `windows_argv` for native Windows command
differences and `{root}` to refer to a fixture's output directory.

`rule-format.json` lists supported rule options and their value types. Unknown
options are rejected so a spelling mistake cannot silently remove a constraint.
Manifest structure and output constraints also have dedicated rule files.

`catalogue.rules.json` checks image and target shapes, named references, matched
runner/platform/profile fields, required image generation, and recipe paths.
Its `relations` declare source collections, reference fields, destination
collections, destination keys, and optional equal fields. Its `paths` declare
required files using entry fields in `{field}` templates. Catalogue test inputs
live in `tests/catalogue.cases.json`. Toolchain compile/run checks are target
`probes` in `ci/build/targets.json`, with expected exit codes and optional output.
