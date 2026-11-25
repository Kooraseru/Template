---
title: Configuration
description: Where project configuration and authored material live.
---

| Path | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | Native build, test and validation jobs |
| `.github/workflows/publish.yml` | Explicit publication |
| `config/targets.toml` | Repository identity and preview settings |
| `config/branches/` | Optional generated branch definitions |
| `config/publishing/releases/settings.json` | Shared release settings |
| `releases/` | Release records and notes |
| `config/issues/` | Label and milestone definitions |
| `dependencies/` | Workspace dependency manifest and lock |
| `content/` | This project's authored documentation and images |

These are the example project's paths, not universal conformance requirements. Adapt the scripts and workflows to your own project.
