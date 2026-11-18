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

Do not add an H1 in the Markdown body: Starlight renders the frontmatter `title` as the page's H1. Follow frontmatter with a brief introduction, meaningful H2 headings, and relative links to the generated guide routes (e.g. `../publishing/`, not `publishing.md`). Keep instructions accurate for the `source` branch. Avoid proposal notes, meeting records, and implementation drafts in published documentation.

Use `content/images/` for illustrations, referenced from the published site under `/images/` (including the Pages base path). The site's favicon is `content/images/favicon.png`; replace that image to customize the browser tab icon for a repository. CI stages it in Starlight's ignored `public/images/` directory and includes it in published assets. The build script automatically copies these assets after Starlight generates the HTML. The website is currently English-only. Starlight automatically builds navigation from the documentation directory and validates page front matter. Use nested directories to group guides, with `sidebar.order` in front matter only when an explicit ordering is needed. Files under `content/docs/repository/` are authored inputs for generated repository documents. Their `{{project.name}}`, `{{branch.name}}`, and `{{branch.source}}` placeholders are resolved by the branch builder, not by Starlight.

## Custom themes

The renderer loads independent stylesheets in cascade order:

| Stylesheet | Responsibility |
| --- | --- |
| `src/styles/layout.css` | Layout and typography, independent of colors. |
| `src/styles/theme/fallback.css` | Complete baseline light and dark palettes. All literal fallback colors live here. |
| `src/styles/theme/native.css` | Progressive enhancement using CSS system colors and `color-mix()` when supported. |
| `content/theme.css` (staged as `src/styles/project.css`) | Optional project-specific branding. |
| `src/styles/theme/forced-colors.css` | Native accessibility colors when forced-colors mode is active. |

Starlight's Auto, Light and Dark selector controls the color scheme. The fallback stylesheet supplies every shared palette token before native colors override it; there are no distributed literal color fallbacks. Chromium intentionally returns a generic accent in ordinary website tabs, so native colors are best-effort and do not represent the browser's actual toolbar theme. A CSS feature query detects support, not whether a browser returns personalized colors.

A normal website cannot query Chrome's complete toolbar theme, Firefox extension themes, or KDE/GNOME theme files. Such details require a browser extension or a native bridge, neither of which is part of this template.

Community [Starlight themes](https://starlight.astro.build/resources/themes/) can also be installed as plugins in the renderer's `astro.config.mjs` when a project needs a more extensive redesign. For one-off changes to Starlight's header, sidebar, or other UI elements, use [component overrides](https://starlight.astro.build/guides/overriding-components/).

During builds, the component copies `content/docs/` into its ignored `src/content/docs/` staging directory. This prevents absolute filesystem paths from appearing as navigation headings. The generated directory is never an authoring location, and `content/docs/repository/` remains excluded from the site.

After installing the component's dependencies, run `npm run dev` from `.github/components/documentation/pages/build/starlight/` to preview. Each new development server start regenerates the staged docs; restart it after adding or moving files. For a CI-equivalent static build, use `node .github/components/documentation/pages/build/starlight/build.cjs` from the repository root.
