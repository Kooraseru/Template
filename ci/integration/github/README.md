# Repository GitHub configuration

Source-owned declarations are discovered by their folder and TOML file shape:

- `.github/labels/*.toml` declares issue and PR label names and styling.
- `.github/projects/<slug>/project.toml` declares a project.
- Optional `fields/`, `views/`, and `automations/` extend that project.

This template ships no labels or projects by default. Adding a declaration
never grants an Actions token new permissions.

`bash ci/run.sh github labels validate` and
`bash ci/run.sh github projects validate` validate declarations offline.
`plan` compares them with GitHub using an authenticated `gh` session and
does not mutate state. `apply` is an explicit local-user operation; hosted
GitHub Actions mutation is deliberately disabled.

Project automations describe issue/PR intake, but **no hosted event listener
or auto-reconciliation is enabled yet**. Do not claim declarations are applied
or events synchronized without separate live verification. Environment
approval cannot elevate `GITHUB_TOKEN` to project-admin privileges.

GitHub branch protection is external authority, not generated from template
ruleset files. Existing repository rulesets are left untouched.
