---
title: Writing documentation
description: Author Markdown documentation, organize navigation, and customize the Starlight theme.
---

Documentation pages live directly inside `content/docs/`. Group related guides by subject when the collection grows; do not introduce another `templates/` directory.

Each authored guide should use YAML front matter with the same keys:

```yaml
---
title: A concise page title
description: One sentence explaining the page's purpose.
---
```

Do not add an H1 in the Markdown body: Starlight renders the frontmatter `title` as the page's H1. Follow frontmatter with a brief introduction, meaningful H2 headings, and relative links to related guides. Keep instructions accurate for the `source` branch. Avoid proposal notes, meeting records, and implementation drafts in published documentation.

Use `content/images/` for illustrations, referenced from the published site under `/images/` (including the Pages base path). The build script automatically copies these assets after Starlight generates the HTML. The website is currently English-only. Starlight automatically builds navigation from the documentation directory and validates page front matter. Use nested directories to group guides, with `sidebar.order` in front matter only when an explicit ordering is needed. Files under `content/docs/repository/` are authored inputs for generated repository documents. Their `{{project.name}}`, `{{branch.name}}`, and `{{branch.source}}` placeholders are resolved by the branch builder, not by Starlight.

## Custom themes

The default site intentionally defines **no fixed color palette**. Its component stylesheet uses the browser's CSS system colors (`Canvas`, `CanvasText`, `LinkText`, `AccentColor`, and the associated text colors) with derived shades through `color-mix()`. Starlight's built-in Auto/light/dark selector selects the color scheme; high-contrast mode uses direct native system colors. This approach may inherit operating-system colors where the browser exposes them, but privacy protections can substitute browser defaults instead of the user's exact OS accent or desktop theme. The optional `content/theme.css` starts without colors and remains available for explicit project branding.

A normal website cannot query Chrome's complete toolbar theme, Firefox extension themes, or KDE/GNOME theme files. Such details require a browser extension or a native bridge, neither of which is part of this template.\n\nCommunity [Starlight themes](https://starlight.astro.build/resources/themes/) can also be installed as plugins in the renderer's `astro.config.mjs` when a project needs a more extensive redesign. For one-off changes to Starlight's header, sidebar, or other UI elements, use [component overrides](https://starlight.astro.build/guides/overriding-components/).

During builds, the component copies `content/docs/` into its ignored `src/content/docs/` staging directory. This prevents absolute filesystem paths from appearing as navigation headings. The generated directory is never an authoring location, and `content/docs/repository/` remains excluded from the site.

After installing the component's dependencies, run `npm run dev` from `ci/components/documentation/pages/build/starlight/` to preview. Each new development server start regenerates the staged docs; restart it after adding or moving files. For a CI-equivalent static build, use `node ci/components/documentation/pages/build/starlight/build.cjs` from the repository root.
