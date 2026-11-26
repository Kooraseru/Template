# Documentation parity

The built documentation must match the independently captured reference in every declared scenario. Check text, geometry, computed presentation, screenshots and observable interaction states. A missing reference is an infrastructure failure by default. During explicitly configured commissioning, an entirely absent scenario baseline produces an UNVERIFIED result (advisory only at warning severity). The candidate must still render successfully. Partial or invalid baselines, browser failures and missing candidate elements remain fatal. Error severity also blocks unverified scenarios.

Experiments are direct directories of experiments/ containing experiment.json. Selectors map equivalent elements rather than requiring identical implementation markup. Each scenario supplies its own viewport, actions, and element mappings. Capture is explicit, writes only to the requested output directory, and must be reviewed before reference files are committed. Never capture from the candidate. Normal checking does not contact the reference website.

This initial implementation compares viewport and selected element screenshots exactly (PNG bytes), text, selected computed CSS values and element dimensions/positions within a configurable CSS-pixel tolerance. Exact PNG comparison is deliberately conservative; browser/font/platform differences may cause failures. It does not yet cover every Creator Hub interaction or full document content. The initial BasePart experiment is not a complete parity certification.

Run the dependency loader, build the documentation, install the pinned Playwright browser using the Starlight package, then:

```sh
node dependencies/packages/checks/ruleLinter/product.cjs documentation build/github/pages build/rules/documentation
```

For explicit reference acquisition append --capture. Review the resulting reference files and copy them into the corresponding experiment's reference/ directory. Capture requires network access and the official reference to render successfully. Reports and screenshots are written under build/. Product checks are not run on editor keystrokes.

Normal CI uses only committed references and never acquires or copies a live baseline. Use the CI workflow's explicit `capture_documentation_reference` dispatch input or the local capture command to acquire evidence. Failed capture attempts retain a diagnostic screenshot, page title and headings; they are never treated as successful reference data. Browser integration tests run in the documentation job before parity checks.
