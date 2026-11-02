# Source-managed repository rulesets

Each direct `.toml` file defines one managed repository ruleset. The filename
is its source identity. `[ruleset]` declares its GitHub name, branch/tag target,
enforcement, and included/excluded refs. `[[rules]]` declares its native REST
rule type and optional `[rules.parameters]`. `[[bypass_actors]]` declares
actor IDs, types, and bypass modes.

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

`source-gate.toml` requires PRs and the `gate` check with no bypass.
`source-admin.toml` separately restricts updates to administrative actors
that can bypass the update rule *through pull requests*. No ruleset overrides
another ruleset's required checks.

Reference: https://docs.github.com/en/rest/repos/rules
