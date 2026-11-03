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
      record/root.md     per-component collapsible diagnostic
    authorization/       credential instructions and evidence
    projects-authorization/
```

Each component owns its diagnostic attachments. They render in collapsible sections
below its full-width results table, never inside table cells. Component identities
still come from the validated scheduler; there is no additional inventory.

Markdown receives named `{{values}}`. A node receives its rendered `{{children}}`.
A `records` glob selects collected response fragments; identical fragments are
shown once and list their affected components. Component groupings are derived
from scheduler identities, so this configuration is not a component inventory.

`templates` associates reusable roles with Markdown paths. `labels` names result
fragments. Paths are relative to this directory.

`palette` stores named solid hexadecimal colors. `buttons` associates a label,
GitHub icon, URL field, and palette color. All buttons and status badges share
`badges.size` and `badges.logo_color`. Buttons with icons use `badges.variant`
(`branded`); badges without icons use `badges.iconless_variant` (`secondary`).
Both use `sm` size. Width follows the label; height, typography, and
padding use the same size everywhere. Add or change a button in TOML, then place
its named `{{..._button}}` value in a response Markdown file.

`colors` supports aliases and the semantic references `github.note`, `github.tip`,
`github.important`, `github.warning`, and `github.caution`. `status_colors` maps
each resolved reference to a palette color. The summary, component outcomes,
and detail headings display these colors as badges with readable alt text.
`status_alert` remains available for templates that use top-level native alerts.
The centered summary uses badges because GitHub alerts cannot be nested inside
other elements. GitHub strips custom CSS text colors; no emoji markers are added.

Root summaries center their text in an HTML container. Overview and component
tables use explicit table and cell alignment so both the tables and their
contents are centered. HTML table values are escaped by the renderer.

Only the CI Start job and CI Execution's final reporting job write job summaries.
Component jobs upload fragments even when they fail. Their logs and job results
remain independent of this presentation layer.

The CI header uses independent Shieldcn badges at default size. The runner badge
uses the actual job operating system (or `CI_RUNNER_LABEL` when explicitly set),
the status uses a fixed charcoal background and a conclusion-colored circle,
and CI Execution reads its available artifact count from the current GitHub
Actions run. The reporting job requests Actions: read for that lookup. If the
count is unavailable, it displays `?` rather than fabricating a total.
