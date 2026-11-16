---
title: Continuous integration
description: Read-only validation, native execution, and publication boundaries.
---

# Continuous integration

The permanent `.github/workflows/ci.yml` delegates orchestration to CI Engine. Feature-branch pushes and pull requests run read-only checks. Trusted pushes to the default `source` branch launch the generated Build, Tests, and Publish graph through the CI Engine's `default_push` route.

The generated graph validates builds, documentation assets, generated branch contents, and distribution staging before entering privileged publication components. Temporary execution branches are removed after completion.

Publication is a separate CI phase after successful Build and Tests. Component-specific jobs receive narrowly scoped GitHub permissions to update the generated `main` branch and deploy Pages. Pull requests and feature-branch builds never receive publication credentials.

See [Publishing](publishing.md) for the destination paths and prerequisites.
