---
title: Continuous integration
description: Read-only validation, native execution, and publication boundaries.
---

# Continuous integration

The permanent `.github/workflows/ci.yml` delegates orchestration to CI Engine. Normal pushes and pull requests run read-only checks. Trusted pushes to the default `source` branch also launch a generated native build-only workflow through `ci/github/workflows/launch.cjs`.

The native run validates build hosts, tests, documentation assets, generated branch contents, and distribution staging. It cannot publish; temporary `ci/run-push-*` branches are removed after execution.

Publication is a separate operation after a successful source-push CI run. The publication workflow uses narrowly scoped GitHub permissions to update the generated `main` branch and deploy Pages. Pull requests and feature-branch builds never receive publication credentials.

See [Publishing](publishing.md) for the destination paths and prerequisites.
