# CI implementation

`.github/workflows/ci.yml` is the single committed workflow. It invokes the
Luau coordinator at `.github/ci/entry.luau`, which discovers component manifests
under `.github/ci/components/` and schedules isolated component runs. Grouping
folders do not establish order; dependencies come from declared capabilities.

Edit CI behavior and component implementations under `.github/ci/`. Edit
scheduler policy, credentials-by-name, response templates, and tool pins under
`.github/automation/`. GitHub API integrations are grouped under
`.github/ci/integrations/github/`. Native GitHub job adapters remain beside the
component that owns them in `github.toml` files.

The standalone Preflight extension reads `.vscode/preflight/plan.json` and
publishes plan diagnostics in the VS Code Problems panel. Its editor diagnostics
API also exposes findings from active VS Code language providers. Preflight does
not replace the component scheduler or execute the CI graph during analysis.