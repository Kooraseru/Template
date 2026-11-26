# Documentation parity

The built documentation must match the independently captured reference in every declared scenario. Check text, geometry, computed presentation, screenshots and observable interaction states. A missing reference is an infrastructure failure, not a passing comparison.

Experiments are direct directories of experiments/ containing experiment.json. Selectors map equivalent elements rather than requiring identical implementation markup. Each scenario supplies its own viewport, actions, and element mappings. Capture is explicit, writes only to the requested output directory, and must be reviewed before reference files are committed. Never capture from the candidate. Normal checking does not contact the reference website.

This initial implementation compares viewport and selected element screenshots exactly (PNG bytes), text, selected computed CSS values and element dimensions/positions within a configurable CSS-pixel tolerance. Exact PNG comparison is deliberately conservative; browser/font/platform differences may cause failures. It does not yet cover every Creator Hub interaction or full document content. The initial BasePart experiment is not a complete parity certification.

Run the dependency loader, build the documentation, install the pinned Playwright browser using the Starlight package, then:

```sh
node dependencies/packages/checks/ruleLinter/product.cjs documentation build/github/pages build/rules/documentation
```

For explicit reference acquisition append --capture. Review the resulting reference files and copy them into the corresponding experiment's reference/ directory. Capture requires network access and the official reference to render successfully. Reports and screenshots are written under build/. Product checks are not run on editor keystrokes.
