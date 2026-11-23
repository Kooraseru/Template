---
title: Template conformance
description: Verify inherited infrastructure against a pinned parent revision.
---

The originating repository declares `conformance.mode: source` in `config/template.json`. Derived repositories declare `conformance.mode: consumer`, `upstream: owner/repository`, and a full 40-character immutable parent `revision`.

The parent maintains `config/template-contract.json`. CI checks the parent's pinned Git tree against the child's protected files, plus matching CI-Engine workflow revision. Missing, modified, or unverifiable protected files fail. Project-owned source, tests, and content are intentionally not protected. Upstream revision drift is advisory and not falsely marked current.

Run `node .github/components/quality/template-conformance/check.cjs` locally or through CI-Engine's read-only `quality/template-conformance` component. Parent updates require reviewed repinning; there is no automatic overwrite.
