---
title: Preview deployments
description: Review temporary documentation websites using Cloudflare Pages.
---

Create a Cloudflare Pages Direct Upload project and configure its name and actual public hostname in the `github.previews` section of `config/targets.toml`.

Set the `CLOUDFLARE_API_TOKEN` secret and `CLOUDFLARE_ACCOUNT_ID` variable in the protected `ci-preview-cloudflare` GitHub environment.

A successful same-repository PR CI run produces a static documentation artifact. The shared CI-Packages documentation action in the separate PR Results workflow checks the current PR head against GitHub, downloads only the static artifact, publishes it to Cloudflare Pages, and updates one PR comment with its URL. Forks are validation-only. No PR code runs with publishing credentials.

Closing a PR runs the retirement workflow against trusted default-branch code. It replaces the alias with an HTTP 410 response and removes earlier deployments for that alias. No temporary Git branch is required.

For manual previews, use Actions → Preview and select the PR or branch target (or its retirement option). The renderer stays project-owned; the shared action accepts the configuration and built static directory as explicit inputs.
