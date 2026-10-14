# CI configuration

`config.toml` selects repository behavior. The existing `validation/config.rules.json` schema supplies
omitted optional fields before validation. Explicit values win, including `false` and
empty arrays. Required sections and their generation/publication flags remain
explicit. Enabling a feature still requires its necessary inputs.

`enabled` controls generation. `publish` permits publication only after successful
checks on a trusted hosted `source` push. Local `act` runs and pull requests never
publish, even when a publication flag is true.

| Category / field | Baseline or omitted value | Meaning |
| --- | --- | --- |
| `repository.enabled` | Baseline `true`; required | Generate the publication tree for `main`. |
| `repository.publish` | Baseline `true`; required | Allow the gated job to update `main`. |
| `repository.include` | Baseline `["src"]`; required | Existing repository paths copied into that tree. |
| `pages.enabled` | Baseline `false`; required | Render Markdown website templates. |
| `pages.publish` | Baseline `false`; required | Allow gated GitHub Pages deployment. |
| `pages.title` | Optional; `"Project documentation"` | Generated site's title. |
| `release.enabled` | Baseline `true`; required | Assemble commit-based channels and distributions. |
| `release.publish` | Baseline `true`; required | Allow gated updates of movable release channels. |
| `images.enabled` | Baseline `true`; required | Build and export selected CI images. |
| `images.names` | Baseline 24 catalogue names; omitted `[]` | Selected image variants; a nonempty selection is required when enabled. |
| `build.runner` | Optional; `"ubuntu-latest"` | Fallback runner when neither targets nor a custom matrix is selected. |
| `build.matrix` | Optional; `[]` | Custom named configurations; a nonempty list overrides `targets`. |
| `build.targets` | Baseline 32 catalogue names; omitted `[]` | Selected targets from `build/targets.json`. Empty matrix and targets select one fallback target named `default`. |
| `build.toolchains` | Optional; `[]` | Extra native Rust/CMake setup; catalogue profiles already select their own setup. |
| `build.rust_version` | Optional; `""` | Explicit version required when extra native Rust setup is enabled. |
| `build.cmake_version` | Optional; `""` | Explicit version required when extra native CMake setup is enabled. |
| `build.commands` | Optional; `[]` | Project build/test command argument arrays; empty means toolchain probes only. |
| `build.package_paths` | Optional; `[]` | Existing paths under `build/` copied into distribution archives; empty means no application payload. |

The populated baseline image and target selections are explicit in `config.toml`,
not hidden fallbacks. See [image profiles](images/README.md) and the two JSON
catalogues for their full names and platform settings.

Release selections live in [releases/channels.toml](releases/channels.toml).
Canary follows source; stable and beta select explicit SHAs. Optional `notes`
adds an authored introduction. See [release channels](releases/README.md) for
ranges, credits, graph defaults, provenance, and required source rulesets.
The old versioned notes remain an unpublished draft. CI images transfer solely
as workflow artifacts; registry publication is retired.

## Generated output

All output under `build/` is ignored and disposable. Create directories when
needed; empty directories do not require `.gitkeep` files.

| Path | Contents |
| --- | --- |
| `build/logs/` | Build logs, local/hosted CI logs, and release-preview logs. |
| `build/cache/` | Downloaded development tools and the local `act` artifact server store. |
| `build/tmp/` | Temporary checkouts, research downloads, and local test configurations. |
| `build/backups/history/` | History-reset recovery backups; retained during organization. |
| `build/reports/` | Generated inspection reports and matrix summaries. |
| `build/tests/` | Test fixture output. |
| `build/releases/` | Channel/SHA release output and local previews. |
| `build/artifacts/` | Distribution packaging output. |

The `act` server store lives in `cache/` because distribution packaging resets
`build/artifacts/`. Keeping those outputs separate protects local transfers when
the workflow uses a shared workspace. Build jobs continue to write their logs
under `build/logs/`; save orchestration logs under `build/logs/ci/`.
