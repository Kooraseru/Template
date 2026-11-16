---
title: Preview deployments
description: Publish temporary Starlight previews from trusted CI without changing production or generated main.
---

Template supports on-demand documentation previews from a trusted source-branch CI dispatch. The selected PR/branch builds in a read-only job; a separate job checks out trusted source code and publishes only the static site artifact.

Preview publication does not update packages, releases, or the generated `main` branch. An explicit maintainer dispatch is required. No new permanent workflow YAML is used.

## Configure the provider

Use the existing `.github/config/targets.toml`:

```toml
[github.previews]
enabled = true
provider = "github-pages" # or "cloudflare-pages"
pull_requests = true
branches = true
path_prefix = "previews"
state_branch = "pages-state"
retention_days = 14
cloudflare_project = ""
```

For GitHub Pages, configure Settings → Pages → Source: GitHub Actions. The first successful trusted `source` Publish run initializes the orphan `pages-state` branch, and subsequent runs preserve active previews.

For Cloudflare Pages, set `cloudflare_project` to an existing Cloudflare Pages project. Create a protected GitHub environment named `ci-preview-cloudflare` containing the secret `CLOUDFLARE_API_TOKEN` and variable `CLOUDFLARE_ACCOUNT_ID`. The token needs Pages Write access. The preview uses Wrangler Direct Upload of prebuilt static files; production remains on GitHub Pages.

## Create a preview

In Actions → CI → Run workflow, select `source` and provide:

| Input | Value |
| --- | --- |
| `operation` | `preview` |
| `publish` | `true` |
| `preview_target` | `pr:50` or `branch:demo/site-redesign` |

Only open same-repository PRs and named branches are accepted. Fork PRs, `source`, and generated CI branches are rejected. The publisher checks that the selected commit did not change while it was being built.

With GitHub Pages, the example address is `https://kooraseru.github.io/Template/previews/pr-50/`. Cloudflare uses `https://pr-50.<project>.pages.dev/Template/`. The actual link appears in the run summary after successful publication.

GitHub Pages previews share the production site origin. Only use that provider for explicitly trusted contributions, because preview scripts execute in the production origin. Cloudflare previews have distinct hostnames.

## Demo-only pages

Create a temporary branch from the implementation PR head, put demonstration pages on it, and publish `branch:demo/site-redesign`. That demo branch is not merged with the implementation PR. There is no reliable `.gitignore` or `.gitattributes` switch that removes already-tracked demo files from a merge.

## Cleanup

For GitHub Pages, dispatch `delete:pr:50` or `delete:branch:demo/site-redesign` with the same `preview` operation and confirmation. That removes the preview in the next combined Pages deployment.

Expired GitHub Pages previews are pruned when another production or preview publication occurs, not by a background timer. Cloudflare Pages can prevent deletion of the latest alias deployment, so the GitHub cleanup command does not apply to the Cloudflare provider.

Production and previews are combined into one GitHub Pages artifact, with file snapshots persisted separately in `pages-state`. Production is stored at the site root, and preview assets under `previews/<id>/`. A shared concurrency group serializes updates.
