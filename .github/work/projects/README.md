# Source-managed GitHub Projects

Each project folder contains `project.json` and `README.md`. The folder name is
the stable source identity. The `project` object defines its owner, title,
visibility, description, and README filename. `fields` defines custom fields and
select options. `views` is optional.

`projects/plan` validates definitions and emits a reviewable plan. `projects/sync`
creates or reconciles projects, fields, repository links, metadata, and Project
views. Retained select option IDs are preserved so existing item values stay
associated. It does not create issues, PRs, draft issues, or project items.

Supported field types are `TEXT`, `NUMBER`, `DATE`, and `SINGLE_SELECT` with
ordered options. A Project view needs a unique name and one of
`TABLE_LAYOUT`, `BOARD_LAYOUT`, or `ROADMAP_LAYOUT`. `filter` is an optional
GitHub view filter expression. Table and board views may set `visible_fields`;
roadmap views do not support that setting through the API. Layout grouping, sort
order, roadmap dates, and view order are UI-managed.

Project views reconcile to the declared list: declared views are created or
updated and undeclared views are deleted. Omitting `views` clears every Project
view, including GitHub's default `View 1` on first sync. Repository-level issue
views are separate and configured in GitHub's **Issues → Views** UI.

## Authorization

The built-in repository `GITHUB_TOKEN` cannot access account-owned Projects.
The apply component tries:

1. An installed organization App using the configured `app_id` and
   `app_private_key` roles, requesting **Organization Projects: write**. Repository
   Projects permission alone is insufficient. Install it for the organization
   and repositories it needs to link.
2. The secret named by `github.credentials.projects_token`, currently
   `CI_PROJECTS_TOKEN`. This can hold a Projects-capable App installation/user
   token or PAT. A classic PAT needs `project` scope and access to linked private
   repositories where applicable. Personal-account Projects need user authorization.

All mappings in repository.toml are secret/variable names, never credentials.
Missing or rejected credentials produce a warning and skip synchronization.

## Reconciliation boundary

The owner defaults to the account from repository.toml's repository path. Each project
has a repository/file management identity stored as a hidden README marker.
Only projects carrying this repository's marker are adopted or pruned. Removing a
blueprint clears its Project views, then closes that managed Project while
retaining all items. Unrelated personal/organization projects are not touched.

Within a managed Project, undeclared custom fields/options are removed. Removing
them can clear corresponding item values; retained options keep IDs. Native
system fields and organization issue fields are not project-owned. GitHub's
Status field is retained; declare its desired choices in the blueprint. Changing
a field's data type fails rather than deleting all values to recreate it.

## Repository issue views, milestones, and automation

Keep one private **Development** Project. Create two saved issue views in
GitHub's Issues dashboard:

- **Development**: private view filtered by `repo:Kooraseru/Template is:open`, for
  personal triage. The private Development Project is the team work surface;
  invite developers and repository admins as Project collaborators.
- **Roadmap**: shared view filtered by
  `repo:Kooraseru/Template is:open label:roadmap`, for public release
  plans. Only apply `roadmap` to issues whose titles and details are suitable for
  public release planning. Do not apply it to security reports or confidential
  work.

The `roadmap` label is source-defined in `.github/work/labels.toml`. GitHub does
not expose a supported API to create/configure saved issue views or to define
built-in Project workflow automations, so configure them in the UI. Keep project
automation out of CI. For Development, use GitHub's built-in **Auto-add to
project** for repository issues and pull requests, **Item closed** to set Status
to Done, and **Pull request merged** to set Status to Done. Auto-archive can
remain optional.

Use GitHub's native repository milestones for releases. Name a milestone with
the release version (for example, `v1.2.0`), add a concise release goal and a
target due date, and assign approved `roadmap` issues to it. Create milestones
only when a release has a real target. Milestones can be maintained through
GitHub's UI or its Issues REST API. This repository does not yet keep a release
milestone catalog; the Roadmap issue view is driven by the `roadmap` label, and
milestones group those issues by release.

References:
- https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/automating-projects-using-actions
- https://docs.github.com/en/graphql/reference/projects
- https://docs.github.com/en/issues/using-labels-and-milestones-to-track-work/about-milestones
- https://docs.github.com/en/issues/planning-and-tracking-with-projects/managing-your-project/managing-visibility-of-your-projects
