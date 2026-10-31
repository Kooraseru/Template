## Projects authorization required

Project synchronization for **{{owner}}** was skipped, not completed.

<details>
<summary>Set up Projects authorization (GitHub CLI or website)</summary>

Choose the instructions for the account that owns the project. You need access
to manage Actions secrets in `{{repository}}`.

### Personal account

1. On GitHub, create a [classic personal access token](https://github.com/settings/tokens/new)
   for a user who can manage the project. Grant the `project` scope and any
   repository access needed for linking. GitHub does not currently support
   fine-grained PATs for user-owned Projects.
2. Add the token as a repository secret using either method:

   **GitHub CLI:** Sign in with `gh auth login`, then run the following on your
   computer and paste the token at the interactive prompt:

   ```sh
   gh secret set {{projects_token}} --repo {{repository}}
   ```

   **GitHub website:** Open `{{repository}}` → **Settings → Secrets and
   variables → Actions → New repository secret**. Name it `{{projects_token}}`,
   paste the token value, and save it.

Creating a classic PAT still requires the GitHub website. `gh auth refresh`
changes the CLI's own authorization; it does not set the Actions secret.

An existing GitHub App user access token may also be supplied in that secret if
it has the required Projects access. This pipeline does not create or refresh
user access tokens; the App ID and private key alone are not user authorization.

### Organization

1. On GitHub, [create or configure an App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app)
   with **Organization Projects: read/write**, install it on the organization,
   and grant access to the repository where needed. Record its App ID and
   [generate a private key](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps).
2. Add the App ID and private key to the repository using either method:

   **GitHub CLI:** Replace `YOUR_APP_ID` and `PATH_TO_PRIVATE_KEY.pem` with
   the App ID and the downloaded key file. In Bash, run:

   ```sh
   gh variable set {{app_id}} --repo {{repository}} --body YOUR_APP_ID
   gh secret set {{app_private_key}} --repo {{repository}} < PATH_TO_PRIVATE_KEY.pem
   ```

   In PowerShell, use this command for the key instead:

   ```powershell
   Get-Content -Raw -LiteralPath 'PATH_TO_PRIVATE_KEY.pem' | gh secret set {{app_private_key}} --repo {{repository}}
   ```

   **GitHub website:** Open `{{repository}}` → **Settings → Secrets and
   variables → Actions**. Under **Variables**, add `{{app_id}}` with the App ID.
   Under **Secrets**, add `{{app_private_key}}` with the full private key.

Alternatively, put a Projects-capable token in the Actions secret named
`{{projects_token}}`, using the secret setup method above. Creating and
installing the App requires GitHub's registration and installation flow.

The names above come from `repo/config/github.toml`. Store actual tokens and
private keys in GitHub Secrets, never in TOML or scripts. The built-in
`GITHUB_TOKEN` cannot access account-owned Projects.

The current sync links each project to this repository. GitHub requires both
to have the same owner for that link. Once a usable credential is available,
the next source push can apply the project definitions. Earlier partial
operations, if any, may remain.

</details>

