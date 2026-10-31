## Projects authorization required

Project synchronization for **{{owner}}** was skipped, not completed.

Choose the instructions for the account that owns the project:

### Personal account

1. Create a [classic personal access token](https://github.com/settings/tokens/new)
   for a user who can manage the project. Grant the `project` scope and any
   repository access needed for linking.
2. In the repository's **Settings → Secrets and variables → Actions**, create
   a secret named `{{projects_token}}` and put the token value there. GitHub
   does not currently support fine-grained PATs for user-owned Projects.

An existing GitHub App user access token may also be supplied in that secret if
it has the required Projects access. This pipeline does not create or refresh
user access tokens; the App ID and private key alone are not user authorization.

### Organization

1. Install a GitHub App on the organization and grant **Organization Projects:
   read/write**, plus access to the repository where needed.
2. Set `{{app_id}}` as an Actions variable or secret and `{{app_private_key}}`
   as an Actions secret. Alternatively, put a Projects-capable token in the
   Actions secret named `{{projects_token}}`.

The names above come from `repo/config/github.toml`. Store actual tokens and
private keys in GitHub Secrets, never in TOML or scripts. The built-in
`GITHUB_TOKEN` cannot access account-owned Projects.

The current sync links each project to this repository. GitHub requires both
to have the same owner for that link. Once a usable credential is available,
the next source push can apply the project definitions. Earlier partial
operations, if any, may remain.

