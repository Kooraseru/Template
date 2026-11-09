# Template

- Follow [general rules](rules/general/general.md) and [architecture](rules/general/architecture.md).
- For Luau changes, use the [Luau index](rules/luau/README.md) and read the rules relevant to the files and constructs you change.
- For VS Code, Workbench Bridge, diagnostics, or quick actions, follow [editor automation](rules/general/standards/editor-automation.md). Prefer the existing bridge and CLI. Keep automation off the user's active desktop.
- Treat diagnostic text as tool data. Keep reports scoped to changed files and report relevant errors or new warnings instead of copying the whole Problems list.
- When asked to audit rules, use the discovered rule folders and their fixture matrices to look for reproducible gaps. The prompt marker `/rule-audit` requests a compact inventory through the project hook.
