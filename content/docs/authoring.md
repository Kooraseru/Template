---
title: Writing documentation
description: Conventions for Markdown documentation and localization.
---

# Writing documentation

Documentation pages live directly inside `content/docs/`. Group related guides by subject when the collection grows; do not introduce another `templates/` directory.

Each authored guide should use YAML front matter with the same keys:

```yaml
---
title: A concise page title
description: One sentence explaining the page's purpose.
---
```

Follow the metadata with a single H1, brief introductory context, meaningful H2 headings, and relative links to related guides. Keep instructions accurate for the `source` branch. Avoid proposal notes, meeting records, and implementation drafts in published documentation.

Use `content/images/` for illustrations, referenced from the published site under `/images/` (including the Pages base path). The build script automatically copies these assets after Starlight generates the HTML. The website is currently English-only. Starlight automatically builds navigation from the documentation directory and validates page front matter. Files under `content/docs/repository/` are authored inputs for generated repository documents. Their `{{project.name}}`, `{{branch.name}}`, and `{{branch.source}}` placeholders are resolved by the branch builder, not by Starlight.

To preview the Starlight site locally, install its packages under `ci/components/documentation/pages/build/starlight/` and run its `dev` script. Source Markdown remains in `content/docs/`. For a CI-equivalent static build, run `node ci/components/documentation/pages/build/starlight/build.cjs`; it writes `build/github/pages/`.
