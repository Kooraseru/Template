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

## Luau module structure

Every Luau file under this directory returns a procedural table module with a
PascalCase identity and a public `Run()` function. Dependencies, types, local
helpers and public functions are separated into their relevant phases. Files
start with their repository path and `--!strict`. They contain no `print` calls,
perform no validation on require, and keep fixture creation inside `Run()`.
These modules own neither independent instances nor entities, so their shape is
the procedural table-module format from the mounted guidance.

Use the existing CI boundary to invoke one module:

```powershell
node ci/control/run-check.mjs ci/validation/workflows.luau
node ci/control/run-check.mjs ci/validation/tests/rules.luau
```

The adapter generates a disposable Lune invocation under `build/validation/`.
It is not a second pipeline: `ci/control/validate.mjs` still selects the checks
for the single workflow. Logging belongs to the caller. Requiring a module only
loads its implementation; fixture tests reset their output even after failure.

`rules.format` owns the supported rule vocabulary. `key_count` counts collection
entries; `count_where` counts entries matching a field; `requires_before` checks
ordered prerequisites. Workflow control counts, the protected gate name and action
setup ordering live in `workflows.rules`. `config.cases.controls` owns manual-control
expectations and baseline preservation. There are no version or shape selectors.

The mounted guidance is tracked under `.kero/mnt/global/language/luau/`; repository
ignore rules explicitly include the snapshot and exclude only local KERO runtime
state. Source-owned global updates still require KERO's mount refresh operation.

## Editor checks

The repository uses Luau's new type solver for `index` and typed lookup surfaces.
Enable `luau-lsp.fflags.enableNewSolver` in the editor. The same setting is recorded
in `.luau-lsp/settings.json`; the analyzer CLI also accepts
`--flag:LuauSolverV2=true`. No diagnostic categories are disabled.
