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

Use `content/images/` for illustrations, referenced by relative paths in Markdown. Locale records live in `content/i18n/<locale>/`; the default language is selected by that locale's `locale.toml`. Files under `content/docs/repository/` are authored inputs for generated repository documents, and their `{{tag:...}}` values are resolved by the branch builder.
