---
title: Preview deployments
description: Review temporary documentation websites using Cloudflare Pages.
---

Documentation previews are hosted by Cloudflare Pages. The authored `source` branch remains independent of the hosted site. The engine creates temporary `ci/run-preview-*` branches to execute CI, deletes them after completion, and uploads the resulting static assets to Cloudflare. No Git branch stores website snapshots.

## Setup

Create a Cloudflare Pages **Direct Upload** project, for example `template`, and set its actual name in `.github/config/targets.toml`:

```toml
[github.previews]
enabled = true
pull_requests = true
branches = true
retention_days = 14
cloudflare_project = "template"
```

Create a protected GitHub environment named `ci-preview-cloudflare` with the `CLOUDFLARE_API_TOKEN` secret (Pages Write permissions) and the `CLOUDFLARE_ACCOUNT_ID` variable. CI does not automatically provision the Cloudflare project or its credentials.

## Publish a preview

From Actions → CI → Run workflow, choose `source`. The operation and preview kind are dropdowns; enter a PR number or existing branch name only when relevant:

| Input | Value |
| --- | --- |
| `operation` | `preview` |
| `publish` | `true` |
| `preview_kind` | `pr` (dropdown; also `branch`, `delete-pr`, `delete-branch`) |
| `preview_pr` | `50` for PR targets; `0` otherwise |
| `preview_branch` | `demo/site-redesign` for branch targets; otherwise blank |

An open PR must originate from the same repository. Forks, closed PRs, `source`, and generated CI branches cannot be previewed. The selected SHA is checked again before publishing, and the build job never receives publishing credentials.

The live address follows the leading-subdomain format `https://pr-50.template.pages.dev/Template/`. Production GitHub Pages keeps its own URL and does not store preview assets.

After a successful PR preview deployment, CI automatically posts a comment in the pull request's **Conversation** tab linking to its actual Cloudflare Pages website and source commit. Subsequent previews edit the same bot comment instead of adding duplicate replies. Branch previews do not post to a PR. This requires the generated publisher's `pull-requests: write` permission; no preview URL is announced before a successful deployment.

## Closing a pull request

After cleanup succeeds, the same bot comment is updated to indicate the preview is closed. The single authored workflow forwards `pull_request_target: closed` to CI Engine, which runs a protected lifecycle component against trusted default-branch code. It does not check out the closed PR's code. The job replaces that PR's Cloudflare alias with an HTTP **410 Gone** Worker, so the ordinary preview URL stops serving the site after successful cleanup.

Cloudflare cannot delete the latest deployment for a branch. Once the 410 deployment succeeds, cleanup lists previous deployments for that exact PR alias and deletes them using the Cloudflare Pages API. The latest 410 deployment stays in place because Cloudflare prohibits deleting a branch's latest deployment. Failed cleanup is reported as a failed job; it does not silently claim the historical URLs were removed.

To retire an alias without closing a PR, choose `delete-pr` or `delete-branch` in the `preview_kind` dropdown and supply the corresponding number or branch name. Native GitHub Actions dropdowns cannot dynamically list existing PRs or branches.

## Demo content

Use a separate `demo/site-redesign` branch based on the implementation PR for pages that must not be merged. Preview that branch, then delete it when no longer needed. `.gitignore` and `.gitattributes` do not automatically remove tracked demo files during a GitHub merge.
