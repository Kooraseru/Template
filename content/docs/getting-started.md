---
title: Getting started
description: Create a project from the template and configure your workspace.
---

1. Select **Use this template** on GitHub, then clone the new repository.
2. Install Node.js 24 and Git. Run `node dependencies/packages/core/dependencyLoader/index.ts`.
3. Replace the example project under `source/`. Update the native workflow under `.github/workflows/ci.yml` and dependency manifest for your project.
4. Run `node dependencies/packages/checks/preflightChecker/index.ts` for local compiler checks; append `--rules` for the rule audit.
5. Open a PR. CI runs without publishing credentials.

See [Configuration](../configuration/) for the existing project paths.
