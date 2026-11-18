---
title: Continuous integration
description: Read-only validation, native execution, and publication boundaries.
---

Push, pull, manual and remote events request independent CI Engine execution. Source and feature pushes and PRs run read-only checks, with same-run native host tests. Publishing requires a separately authorized operation.

The engine validates builds, documentation assets, generated branch contents and distribution staging before entering privileged publication components. There are no temporary execution branches.

Publication is a separate CI phase after successful Build and Tests. Same-run component-specific permission lanes receive narrowly scoped GitHub permissions to update the generated `main` branch and deploy Pages. Pull requests and feature-branch builds never receive publication credentials.

See [Publishing](publishing.md) for the destination paths and prerequisites.

## Publication rehearsal

Select `publish-check` in Manual to compile and lint the actual configured Build and Publish workflows and run the consumer regression suite, including a loopback-only publication integration test. No production credentials are forwarded for this operation. Normal validation performs the same tests. Actual `publish` is available only on the default branch with explicit publication confirmation; it can change configured GitHub resources and is not a dry run.
