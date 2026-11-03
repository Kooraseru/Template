# Source-managed GitHub Projects

Each direct `.toml` file defines one Project. Its filename is the source identity,
while `project.title` is the GitHub display name. Adding a valid file includes
it automatically; there is no central project list. Each file owns the
`[project]` section, a multiline `project.readme`, its `[[fields]]`, and
multiple `[[views]]`.

`projects/plan` validates definitions and emits a reviewable plan. `projects/sync`
creates or reconciles projects, fields, single-select choices, repository links,
metadata, and views. It preserves the IDs of retained options, so their existing item
values remain associated. It does not create issues, PRs, draft issues, or project
items. Priority choices are defined here; issue priority is not inferred.

Each `[[views]]` needs a unique `name` and a GitHub GraphQL layout:
`TABLE_LAYOUT`, `BOARD_LAYOUT`, or `ROADMAP_LAYOUT`. Optional `filter` is
a GitHub view filter expression. For table and board views only, optional
`visible_fields` is an ordered list of field names from that Project and the
built-in `Title`. Roadmap views do not support `visible_fields` through the API.
Omitting either supported setting preserves GitHub's existing value.
Layout-specific grouping, sort order, roadmap dates, and view ordering cannot
currently be written through the public view mutation.
Unsupported keys fail validation. Existing undeclared views remain untouched;
renaming a view creates a second view because GitHub exposes no stable
repository-owned view identity.

## Authorization

The built-in repository GITHUB_TOKEN cannot access account-owned Projects.
The apply component tries:

1. An installed organization App using the configured `app_id` and
   `app_private_key` roles, requesting **Organization Projects: write**. Repository
   Projects permission alone is insufficient. Install it for the organization
   and repositories it needs to link.
2. The secret named by `github.credentials.projects_token`, currently
   `CI_PROJECTS_TOKEN`. This can hold a Projects-capable App installation/user
   token or PAT. A classic PAT needs `project` scope and access to linked private
   repositories where applicable. Personal-account Projects need user authorization.

All mappings in github.toml are secret/variable NAMES, never actual credentials.
Values stay in GitHub Secrets. Only the privileged component declaring these
roles receives them; other component child processes do not inherit them.
Temporary App installation tokens are revoked after use.

Missing/rejected credentials produce a warning naming the required App/secrets,
a setup guide in the run summary, and a skipped sync outcome. Other independent
pipeline work continues. Earlier partial operations can remain if a later request
fails; the run does not claim the whole sync completed. Non-authorization API or
configuration errors remain actual failures, not successful skips.

## Reconciliation boundary

The owner defaults to the account from github.toml's repository path. Each project
has a repository/file management identity stored as a hidden README marker.
Only projects carrying this repository's marker are adopted or pruned. Removing a
blueprint closes matching managed projects for the configured owners, retaining
all items. Unrelated personal/organization projects are not touched.

Within a managed project, undeclared custom fields/options are removed. Removing
them can clear their corresponding project field values; retained options keep
IDs. Native system fields and organization issue fields are not project-owned.
GitHub's Status field is retained; declare its desired choices in the blueprint.
Changing a field's data type fails clearly rather than deleting all its values to
recreate it. Automatic item movement and layout-specific settings remain UI-owned.

The public API does not expose every UI workflow/automation setting. Unsupported
blueprint keys fail validation rather than pretending to apply them. Supported
field types are TEXT, NUMBER, DATE, and SINGLE_SELECT with ordered options.

References:
- https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/automating-projects-using-actions
- https://docs.github.com/en/graphql/reference/projects
