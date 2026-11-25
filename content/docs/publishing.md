---
title: Publishing
description: Publish generated branches, release artifacts and GitHub Pages.
---

From the default branch, open Actions → Publish → Run workflow and choose a target. The default `rehearse` validates artifacts without external writes. Use protected environments restricted to your default branch.

## Releases

Add a version directory under `releases/` with a release record and notes. Shared settings live in `config/publishing/releases/settings.json`. CI stages and verifies assets and the historical source commit. Choose `releases` to publish using the job-scoped GitHub token. Existing releases follow the configured conflict policy.

## Generated branches

The branch builder stages `build/github/branches/` from `config/branches/`. Choose `branches` to publish. Initial branch creation is orphaned; updates preserve history, and the default branch is never overwritten.

## GitHub Pages

The Starlight builder stages the site in `build/github/pages/`. Select GitHub Actions as the Pages source in repository settings and choose `pages` from Publish. The native Pages action receives only the necessary Pages and OIDC permissions.

For labels and milestone reconciliation, use Maintenance with its explicit target dropdown. Registry-specific GitHub Packages adapters are not included; the example records are staged as fixtures.
