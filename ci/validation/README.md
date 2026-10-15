# Declarative checks

Define validation constraints and test inputs with their expected results in
`ruleset.json`. Each top-level section owns one behavior. There is no independent
version field or architecture selection. Luau scripts load those definitions and execute the
checks; adding a case should not require adding a Luau assertion or callback.

`config.rules` defines the CI configuration constraints. Its rule paths use
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

Each behavior's `cases` section preserves its executor input document, including
case lists, fixture roots, baseline patches, or configuration/path case groups.
Validators read `<behavior>.rules`; test scripts read `<behavior>.cases`.
Repository checks use `repository.checks` and the rule vocabulary uses `rules.format`.

A cases document may declare a `baseline` patch for its executor to apply before
individual cases. Catalogue cases use this to keep their fixture independent of
the consuming repository's selected targets and optional image jobs.

Publication eligibility lives in `ci/access/publication.rules.json`.
Workflow structure and gate expectations live in `workflows.rules` and
`gate.rules`. Filesystem checks live in `repository.checks`.
Build fixtures use `*.fixture.json` for files, commands, expected exit codes,
and optional expected output. Use `windows_argv` for native Windows command
differences and `{root}` to refer to a fixture's output directory.

`rules.format` lists supported rule options and their value types. Unknown
options are rejected so a spelling mistake cannot silently remove a constraint.
Manifest structure and output constraints also have dedicated rule files.

Configuration rules may declare `default` for an omitted field. The configuration
loader applies those values before validation; explicitly configured values win.
Required categories and publication flags are still validated. Blank optional
settings do not need assignments in `ci/config.toml`.

`catalogue.rules` checks image and target shapes, named references, matched
runner/platform/profile fields, required image generation, and recipe paths.
Its `relations` declare source collections, reference fields, destination
collections, destination keys, and optional equal fields. Its `paths` declare
required files using entry fields in `{field}` templates. Catalogue test inputs
live in `catalogue.cases`. Toolchain compile/run checks are target
`probes` in `ci/build/targets.json`, with expected exit codes and optional output.

## Luau responsibilities

The scripts in this directory and `tests/` are entry points. Shared validation
operations use procedural table modules with PascalCase bindings and public
functions (`Rules.Read`, `Rules.Validate`, `Cases.Apply`, `Cases.Check`). Helpers
remain local camelCase functions. Single-operation helpers return a function.
Every Luau file starts with its repository path and `--!strict`.

`rules.format` owns the supported rule vocabulary. `key_count` counts collection
entries; `count_where` counts entries matching a field; `requires_before` checks
ordered prerequisites. Workflow control counts, the protected gate name and action
setup ordering are declared in `workflows.rules`, not in Luau assertions.
`config.cases.controls` owns manual-control expectations and baseline preservation.
Raw decoded data stays `unknown` until a boundary check; rule and fixture document
shapes stay quarantined in their readers. Public validation APIs expose named
contracts or `unknown`, without `any` casts.

The mounted Luau guidance is under `.kero/mnt/global/language/luau/`. These CI
utilities own no entities or independent object lifetimes, so ECS and OOP
structures do not apply to them.
