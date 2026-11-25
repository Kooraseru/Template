---
title: Continuous integration
description: Native GitHub Actions validation and publication boundaries.
---

The CI workflow runs on pushes and pull requests. Its jobs perform independent local tooling checks, discover host contracts, build binaries, run native tests, build documentation and stage publication artifacts. The final `CI Required` job requires every prerequisite to pass.

CI has read-only credentials. GitHub Actions handles dependencies between jobs and artifact transport directly.

Open Actions → Publish → Run workflow and select `rehearse` to exercise the publication preparation without modifying GitHub releases, generated branches, or Pages. Select a real target only on the default branch.

See [Publishing](../publishing/) for the destination paths and prerequisites.
