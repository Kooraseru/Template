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
Collected response fragments are deduplicated and attached to every affected
component. The renderer preserves shared guidance and navigation anchors while
keeping long instructions outside tables.

`templates` associates reusable roles with Markdown paths. `labels` names result
fragments. Paths are relative to this directory.

`palette` stores named solid colours for component result badges and navigation
buttons. `buttons` associates each navigation link with its destination and icon.
These use the default-size shared badge configuration. Header badges are
configured separately under `[header]` so runner, outcome, and artifact colours
are independent. Add or change a button in TOML, then place its named
`{{..._button}}` value in the response Markdown.

`colors` supports aliases and the semantic references `github.note`, `github.tip`,
`github.important`, `github.warning`, and `github.caution`. `status_colors` maps
each resolved reference to a palette color. Component outcomes display these colours as badges with readable alt text.
`status_alert` remains available for templates that use top-level native alerts.
The centered summary uses badges because GitHub alerts cannot be nested inside
other elements. GitHub strips custom CSS text colors; no emoji markers are added.

The header, overview, and navigation are centred. The component groups and
results tables use the available width, with a narrow outcome column and
wrapping notes. HTML table values are escaped by the renderer.

Only the CI Start job and CI Execution's final reporting job write job summaries.
Component jobs upload fragments even when they fail. Their logs and job results
remain independent of this presentation layer.

The CI header uses independent Shieldcn badges at default size. The runner badge
uses the actual job operating system (or `CI_RUNNER_LABEL` when explicitly set),
the status uses a fixed charcoal background and a conclusion-colored circle,
and CI Execution reads the current workflow artifact count through the GitHub
Actions API and includes the known final `ci-report` upload. The reporting job
requests Actions: read for that lookup. If the API is unavailable, the badge
shows `?` rather than claiming an unverified total. A failed final upload can
leave that projected count one higher than the eventual artifact inventory.
