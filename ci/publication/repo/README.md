# Repository publication

`build.luau` returns the procedural `Repository` module. `Run()` reads validated
CI configuration and source-run context; `Generate(config, publication)` accepts
those values explicitly. Requiring the module does not generate files or log.

Generation resets `build/repo`, copies selected source inputs while excluding
nested Git/build state, overlays `templates/`, and adds optional root licensing
files. `publication.json` records the source commit and repository identity.
Templates are editable source; generated copies are disposable output.

The workflow invokes the module directly through the Node-free
`.github/actions/run-luau` adapter. The module does not publish branches.
`publish.sh` remains the separately authorized publication operation: it checks
the staged identity and current source, then updates generated `main` using the
automatic workflow token. Local or untrusted executions cannot publish.

The Luau module is covered by the module policy, StyLua settings and strict LSP
analysis. To generate locally without publishing:

```powershell
bash .github/integration/run.sh publication/repo/build.luau
```
