---
title: Configuration
description: Where repository, CI, branch, and publishing settings live.
---

The authoritative repository configuration lives under `config/`.

| Path | Purpose |
| --- | --- |
| `targets.toml` | Repository target aliases, publication switches, and bootstrap settings |
| `branches/main.toml` | Source globs included in the generated `main` branch |
| `ci/engine.json` | External CI engine operations and event routing |
| `ci/operations.json` | Native and local adapter operation catalog |
| `.github/components/` | Enabled quality components |
| `publishing/` | Package, release, and attestation configuration |

Change settings in `source`, not in generated branches. The published `main` branch is built from `branches/main.toml` and the authored repository documents in `content/docs/repository/`.
