# Rule directories

A rule directory owns its explanation, optional `check.luau`, and optional
`tests/`. The shared workspace task discovers checkers recursively; it does not
maintain a list of rule names. Lute, Luau LSP, StyLua, and Node run checks their
existing engines already provide. Add a custom checker only when those tools do
not cover the rule. Rules without a checker remain manual review guidance.

Rule groups use `luau/`, `bash/`, `rust/`, `javascript/`, `html/`, `css/`,
`architecture/`, `standards/`, and `workflows/`. Shared language principles
live in [the language system](language-system/README.md).
