# Luau tool configuration

The template keeps developer tooling configuration under `config/luau/`:

- `.luaurc`: strict mode, linting, and development aliases
- `luau-lsp/settings.json`: defaults merged into local VS Code settings by `bash ci/run.sh configure-editor`
- `luau-lsp/standard.d.luau` and `luau-lsp/lune/`: Lune API declarations
- `stylua/.stylua.toml` and `stylua/.styluaignore`: StyLua formatting configuration

Since these are not at the repository root, callers that run StyLua or Luau LSP from the root must select their config paths explicitly. For example:

```bash
stylua --config-path config/luau/stylua/.stylua.toml --check ci
```

The editor settings adapter sets `stylua.configPath` and `luau-lsp.server.baseLuaurc` explicitly. Avoid adding root-level copies of these files; they would create a second authority for configuration.
