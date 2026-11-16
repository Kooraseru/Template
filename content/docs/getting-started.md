---
title: Getting started
description: Create a project from the template and work from the source branch.
---

# Getting started

1. Select **Use this template** on GitHub to create a new repository.
2. Work on the `source` branch, which remains the default development branch.
3. Review the settings under `.github/config/`, particularly `targets.toml`, `ci/engine.json`, and `branches/main.toml`.
4. Edit project sources under `source/` and author documentation under `content/docs/`.
5. Push to `source` to run CI. A successful source push makes generated validation results available before publication.

The `main` branch is generated output. Do not make authoring changes there; update `source` and let publication regenerate it.
