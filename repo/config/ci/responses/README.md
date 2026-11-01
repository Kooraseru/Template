# CI responses

`responses.toml` defines two roots: `start` and `execution`. Each root and child
node selects a Markdown file. Add deeper `children` tables to build a response
tree. `order` affects display only; it does not change component execution.

```text
responses/
  responses.toml
  start/
    root.md              CI Start root
    overview/root.md     CI Start summary and navigation buttons
  execution/
    root.md              CI Execution root
    overview/root.md     CI Execution summary and navigation buttons
  shared/
    components/
      root.md            component tree
      group/root.md      reusable grouping layout
      component/root.md  reusable leaf layout
    records/
      root.md            details and next steps
      record/root.md     one deduplicated result
    authorization/       credential instructions and evidence
    projects-authorization/
```

Markdown receives named `{{values}}`. A node receives its rendered `{{children}}`.
A `records` glob selects collected response fragments; identical fragments are
shown once and list their affected components. Component groupings are derived
from scheduler identities, so this configuration is not a component inventory.

`templates` associates reusable roles with Markdown paths. `labels` names result
fragments. Paths are relative to this directory.

`gradients` stores reusable two-color Shieldcn palettes. `buttons` associates a
label, GitHub icon, URL field, and palette. Button image URLs are built by the
response renderer from those records. Set `buttons.defaults.size` to `default`
for the standard Shieldcn size. Add or change a button in TOML, then place its
named `{{..._button}}` value in a response Markdown file.

`colors` supports aliases and GitHub's native `github.note`, `github.tip`,
`github.important`, `github.warning`, and `github.caution` references. These select
native alert styles. GitHub controls the theme colors;
arbitrary Markdown text colors are not supported. No emoji markers are added. Alert syntax stays readable as a
blockquote on surfaces without alert rendering.

Only the CI Start job and CI Execution's final reporting job write job summaries.
Component jobs upload fragments even when they fail. Their logs and job results
remain independent of this presentation layer.
