# Rules

The files in this directory restore the original rule organization from
`Kooraseru/personal-global-rules` at commit
`c957a1a630bbdfd84401aa2df7372387e91b0a9a`.

- `architecture.md` and `general.md` contain shared, language-neutral guidance.
- `languages/` contains shared language guidance and language-specific rule
  trees. Luau and Rust structure guidance remains under those languages.
- `standards/` and `workflows/` retain their original groupings.

Workspace checker implementations and their fixtures are kept alongside the
closest applicable rule. They are additions to the restored guidance; they do
not redefine the original taxonomy.

## Executable checks

A rule can add a colocated `check.<extension>` entrypoint and a `tests/` folder
with `valid.*` and `invalid.*` fixtures. The checker declares its runtime in a
comment near the top of the file, such as `-- rule-runner=lune` or
`// rule-runner=node`. Preflight discovers these entrypoints under `rules/`
without a registry or TOML entry, runs each checker with `--test .` to verify
its fixtures, then with `--check .` to scan the workspace. A checker reports
findings on stdout as `path:line:column: error|warning|information|hint:
message` and exits successfully when it ran correctly; a nonzero exit means the
checker itself failed. Use native analysis tools when the rule needs them, and
keep the rule’s scope and exclusions in its checker.
