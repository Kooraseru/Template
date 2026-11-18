---
title: Publishing
description: Generated main branch and GitHub Pages publication paths.
---

Publication runs as the Publish stage of the CI Engine-generated execution graph on the default `source` branch. Feature branch pushes and pull requests use read-only validation.

## Generated main branch

The branch generator stages `build/github/branches/main/` according to `config/branches/main.toml`. The branch publication component updates the GitHub `main` branch from that directory. Edit the sources and repository-document templates in `source` rather than modifying `main` directly.

## GitHub Pages

The Pages builder reads Markdown from `content/docs/` and static assets from `content/images/`, producing `build/github/pages/`. Files in `content/docs/repository/` are reserved for generated repository documents and are not published as site pages.

The Pages publication component uploads the Starlight build artifact and deploys it using GitHub Actions. In repository **Settings → Pages**, set the source to **GitHub Actions**; repository Pages availability and permissions are still controlled by GitHub.

The `branches` and `pages` switches in `config/targets.toml` control these publication targets. Starlight is configured under `.github/components/documentation/pages/build/starlight/`; this directory contains renderer configuration, not authored documentation.
