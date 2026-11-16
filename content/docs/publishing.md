---
title: Publishing
description: Generated main branch and GitHub Pages publication paths.
---

# Publishing

Publication runs after a successful CI run initiated by a push to the `source` branch. Before publishing, the workflow verifies that the successful run still refers to the current source revision.

## Generated main branch

The branch generator stages `build/github/branches/main/` according to `.github/config/branches/main.toml`. The branch publication component updates the GitHub `main` branch from that directory. Edit the sources and repository-document templates in `source` rather than modifying `main` directly.

## GitHub Pages

The Pages builder reads Markdown from `content/docs/` and static assets from `content/images/`, producing `build/github/pages/`. Files in `content/docs/repository/` are reserved for generated repository documents and are not published as site pages.

The publication workflow uploads the Pages artifact and deploys it using GitHub Actions. In repository **Settings → Pages**, set the source to **GitHub Actions**; repository Pages availability and permissions are still controlled by GitHub.

The `branches` and `pages` switches in `.github/config/targets.toml` control these publication targets. MkDocs is not installed or configured in this version.
