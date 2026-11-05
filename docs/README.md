# Documentation templates and translations

`docs/templates/` is the language-independent source for repository documents
and site pages. `docs/i18n/<locale>/` mirrors its relative category and filename
stem, with TOML tag records such as `repo/README.toml` and `site/index.toml`.
Locale directories are discovered automatically. A locale can own its display
name and default marker in `locale.toml`; there is no central locale inventory.

Templates remain authored source even when no translation exists. Missing locale
pages or tag values fall back to the default locale and then the template content.
The renderer preserves its supported tags, substitutions, and locale navigation.
GitHub Pages, Wiki, and generated repository branches consume documentation but
do not own its source files.