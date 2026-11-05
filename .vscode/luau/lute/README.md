# Workspace diagnostics

Mandolin lints every workspace Lua/Luau file in the background, including files
that are not open in an editor. It refreshes diagnostics after buffer edits and
saved file changes, using the same Lute configuration as the editor.

Preflight runs `.vscode/preflight/workspace-checks.js` through the Extension
Host's diagnostic provider. It discovers each `rules/**/check.luau` checker,
runs its valid/invalid fixtures, checks JavaScript syntax with Node, and reports
StyLua differences in Problems. Checks run without opening a terminal and do
not change files. This workspace provider needs Node.js and MSYS2 Bash on
Windows; install both Kooraseru Extension Host and Preflight extensions.

Luau LSP has workspace diagnostics enabled for type analysis. Mandolin runs
Lute for unopened workspace files as well as open and saved files.

The declarative-data rule warns about large uppercase boolean maps so they can be
reviewed for conversion to data. Its test fixtures live beside the checker.
