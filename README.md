# Template source

`source` is the authored branch. `main` is generated publication output.
This repository supplies the CI controller; it has no application or host
implementation by default.

## Commands

Run from the repository root with Lune installed:

```bash
bash ci/run.sh rules check
bash ci/run.sh rules sync
bash ci/run.sh preflight list
bash ci/run.sh preflight run
bash ci/run.sh validate
bash ci/run.sh github labels validate
bash ci/run.sh github projects validate
```

`preflight` inspects saved Luau files without running them. Its current
language-analysis frontend checks syntax and types on Linux and Windows when
the pinned analyzer is installed; branch-by-branch previous-state tracing is
still being developed. A missing analyzer is reported as unavailable, not
as success.

## Application builds

Put application implementations and native manifests under `source/`.
The source-owned `source/build.toml` selects real build targets, environments
and packaging paths. Build execution goes through `bash ci/run.sh targets-build`
in the appropriately configured CI job – it is not a standalone host
emulator.

Host implementations belong at `source/hosts/<platform>/`, with actual
build code and matching architecture targets. Do not declare a host or target
just to fill a matrix. The template ships zero buildable hosts.

GitHub labels and Projects are optional folder-discovered declarations.
`validate` is offline. `plan` and `apply` require an authenticated
local `gh` session; hosted Actions cannot mutate them. Approval of a
workflow does not elevate its token permissions.

Signing, authorization, artifacts and publication remain CI responsibilities.
No secrets or personal tokens are required merely to validate this template.
