# Luau linting

Lute provides the lint engine; Mandolin runs the same custom rules in VS Code and publishes diagnostics in the Problems panel. The pinned runtime is installed by `dependencies/lute/bootstrap.sh` into ignored generated output under `build/run/`.

Run the pinned linter from the repository root:

```sh
bash dependencies/lute/bootstrap.sh lint --json repo/ci
```

The adjacent `.config.luau` loads the rules in `rules/` and excludes generated and downloaded files. Keep rules conservative and explainable. In particular, `declarative_data` warns about large uppercase boolean maps as a prompt to consider JSON, TOML, or a schema; it does not prohibit runtime lookup tables. The rule inspects Lute's AST, so it also works on Mandolin's unsaved editor buffers.

Mandolin sends source as Lute string input. Lute custom rules receive the AST but not the original text or a file path in that mode, so rules that inspect comments, headings, or other trivia cannot reliably run in the editor. Keep those checks in a separate source-aware lint path until the editor integration provides source text.

Mandolin is recommended in `.vscode/extensions.json`. Its settings point to the pinned local Lute runtime and shared lint configuration; run the `Lute: Install pinned runtime` task once before expecting editor diagnostics.
