# Source-managed repository rulesets

Each direct `.json` file defines one managed repository ruleset. The filename
is its source identity. The `ruleset` object declares its GitHub name, branch/tag
target, enforcement, and included/excluded refs. The `rules` array declares
native REST rule types and optional `parameters`; `bypass_actors` declares actor
IDs, types, and bypass modes.

`rulesets/plan` validates configurations without touching GitHub. On pushes
to source, `rulesets/sync` reconciles rulesets of matching names with the
GitHub REST API. Unknown remote rulesets are never removed. Changing a managed
ruleset's GitHub display name currently requires renaming its existing remote
rule manually; otherwise the new name creates a separate ruleset.

The standard GITHUB_TOKEN cannot administer repository rulesets. Configure
`github.credentials.rulesets_token` (default secret `CI_RULESETS_TOKEN`)
with repository Administration: write, or provide an installed GitHub App with
repository Administration: write. A classic PAT needs the `repo` scope.
Without an authorized credential, sync explicitly skips; plan/PR validation
continues. Once authorized, API errors are failures, never successful skips.

`source-gate.json` requires PRs and the `gate` check with no bypass.
`source-admin.json` is a disabled tombstone for the former administrator-only
update restriction. Keep it disabled until it is safely retired from the remote
ruleset catalog. The active PR and CI gate remains the only source branch rule
that blocks merges. No ruleset overrides another ruleset's required checks.

Reference: https://docs.github.com/en/rest/repos/rules
