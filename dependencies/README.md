# Workspace dependencies

Edit `dependencies.json` and run `node dependencies/packages/core/dependencyLoader/index.ts --update-lock` to resolve changes. Commit the manifest and `dependencies.lock` together. Normal setup reads the lock and installs into `dependencies/managed/`. The npm provider writes a native manifest and lock under `dependencies/managed/npm/` and runs `npm ci --ignore-scripts`. Release executables live under `dependencies/managed/bin/`. Use `--exec luau.lute --version` to set up dependencies and run a provider's executable.

## Provider declarations

The manifest maps provider names to a built-in name or an explicit argument array. An external provider can use any runtime already available on the host. Keep its bootstrap files outside the generated install. A workspace script named directly in its command is included in the lock fingerprint. List other workspace files the command depends on in the provider's optional `inputs` array.

Each dependency has an ID, a provider name, provider-owned `options`, and an optional list of other dependency IDs in `needs`. The loader resolves and installs in dependency order. Provider prerequisite exports may point at temporary staging files during either operation, so copy their contents or use them during the invocation.

## Command protocol

The loader runs the command from the workspace root with one JSON request on stdin. Write exactly one JSON response to stdout and send human-readable logs to stderr. A nonzero exit fails the operation. The provider command is trusted workspace code and runs with the same permissions as the loader.

Both actions receive `action`, `id`, `options`, absolute `workspace` and `stage` paths, Node's `platform` and `arch` names, and `prerequisites`. The latter maps prerequisite IDs to their named exports as absolute paths.

- **Resolve** receives optional `previous` resolution data from the lock. Return `{ "resolution": ... }` with all pins needed to repeat the install, or `null` for a dependency with no external resolution. Keep resolution data portable between supported platforms and free of secrets. If any resolve fails, the tracked lock stays as it was.
- **Install** receives the selected `resolution`. Write new artifacts under `stage` and return a publication description like the following. Managed exports refer to the final destination. Workspace exports refer to an existing workspace file or directory outside generated and local state locations. An executable names an export and can specify an interpreter argument array. The loader appends the exported file and the user's arguments.

```json
{
  "outputs": [{ "from": "tool", "to": "bin/example" }],
  "exports": { "cli": { "root": "managed", "path": "bin/example/cli.mjs" } },
  "executable": { "export": "cli", "interpreter": ["node"] }
}
```

Use forward slashes in output paths. Paths in `from` are relative to the stage and paths in `to` are relative to `dependencies/managed/`. An output can be a file or a directory. Return `"outputs": []` when exposing only existing workspace files. The loader rejects overlapping destinations and escaping links. It stages the whole install before publication and can recover an interrupted publication on the next run.

The export root `managed` resolves inside `dependencies/managed/`. Legacy provider responses with `root: "build"` remain accepted as an alias during migration; they do not resolve inside `build/`.

`build/` is disposable output. `dependencies/managed/` holds installed dependencies and loader state; `.workspace/` holds persistent local editor, agent, and CI execution state. Both are ignored. Setup copies old `build/dependencies/` under the old loader lock and publishes the copy atomically; the original remains a recovery copy. Existing new-layout installations take precedence. Session selections from `build/run/editor-problems/` are copied without overwriting existing selections. Setup never cleans `.workspace/`. Remove legacy copies only after verifying your installation; no user data is deleted by this migration.

Workspace setup also generates the ignored root `.actrc` from `.vscode/config/act/actrc` so standard act and editor workflow buttons share the same local options.
