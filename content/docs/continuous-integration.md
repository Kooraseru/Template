---
title: Continuous integration
description: Read-only validation, native execution, and publication boundaries.
---

The grouped push, pull, manual and remote workflows delegate orchestration directly to CI Engine. Feature-branch pushes and pull requests run read-only checks. Trusted default-branch pushes additionally launch the generated Build and Tests graph. Publishing requires a separately authorized operation.

The generated graph validates builds, documentation assets, generated branch contents, and distribution staging before entering privileged publication components. Temporary execution branches are removed after completion.

Publication is a separate CI phase after successful Build and Tests. Component-specific jobs receive narrowly scoped GitHub permissions to update the generated `main` branch and deploy Pages. Pull requests and feature-branch builds never receive publication credentials.

See [Publishing](publishing.md) for the destination paths and prerequisites.
