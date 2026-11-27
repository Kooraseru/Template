# Documentation parity

The rule compares Template's rendered documentation against independently captured reference sources. The reusable renderer, browser acquisition and comparison code live in CI-Packages; this rule owns the source registry, policy and evidence.

## Configuration

`.vscode/config/rules.json` contains the authoritative list in `documentation/parity.settings.sources`. Each entry supplies an ID, HTTPS URL and workspace-relative evidence directory. The per-rule schema is `settings.json`. Hash-only class normalization is also configured there. Adding a reference does not require comparison code changes or another published page.

`references/` stores normalized, lossless tag/class/child-order trees with capture provenance and SHA-256 digests. The ten Creator Hub references were captured independently of the candidate. Raw browser exports are not committed or served. The snapshots cover the article root, not the surrounding navigation or all attribute values and interaction states.

`experiments/` declares explicit full-document comparisons. BasePart has four independently measured scenarios. Its structural snapshot is shared with the configured source registry rather than duplicated. Measured scenario metrics and screenshot digests remain in the experiment reference directory.

## Reports and acceptance

Normal validation performs no live reference acquisition. It compares the candidate against the directly paired experiment and uses the whole configured corpus to catalogue observed named component variants. Reports under `build/rules/documentation/parity/`:

- `report.json`: rule status and findings.
- `component-report.json`: matching, different, untested and unexpected named component identities, with source provenance and candidate subtree hashes.
- `corpus-report.json`: registered reference catalogue and observed variants.
- Per-scenario metrics, screenshots and full root-relative structural differences.

An untested source variant is not a missing public page or a parity pass. Unrelated document instance counts are not candidate requirements. Structural names alone do not pass: matching subtree hashes include ordered descendants. Direct document checks still detect differences in nesting, order, geometry, text, selected computed CSS and interaction states. Screenshot comparison uses exact PNG digests; the original reference PNGs are in the original capture artifact recorded by `experiments/base-part/reference/provenance.json`, and are not currently committed.

The rule remains advisory at warning severity while the renderer is corrected. Missing/malformed configured evidence and infrastructure errors fail closed. Commissioning permits an entirely missing measured scenario only when explicitly enabled. Missing partial reference evidence and browser failures remain errors.

## Run

```sh
node dependencies/packages/core/dependencyLoader/index.ts
node dependencies/managed/packages/documentation/build/renderer/build.cjs
cd dependencies/managed/packages/documentation/build/renderer
npx --no-install playwright install chromium
cd - 
node dependencies/packages/checks/ruleLinter/product.cjs documentation build/github/pages build/rules/documentation
```

Explicit acquisition uses the CI workflow input `capture_documentation_reference` or the product checker with `--capture`. Review the separately emitted capture before replacing independent evidence. Routine CI never overwrites baselines.

The package revision is pinned in `dependencies/dependencies.json` and the dependency lock. Template's authored documentation remains exactly two published pages.

`settings.candidates` explicitly selects the two published routes for the component audit, independent of the BasePart full-document experiment. `settings.componentPolicy.required` identifies eight core component identities that must be exercised; their absence is a missing-component finding. Optional components and unseen reference variants remain untested, not passed. Exclusions require an explicit reason; no exclusions are configured. The report distinguishes these states instead of declaring the nine additional references unverified pages.
