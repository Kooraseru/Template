## Projects authorization required

Project synchronization for **{{owner}}** was skipped, not completed. Choose
the setup method you prefer; both require access to manage Actions secrets in
`{{repository}}`.

The Projects synchronization component declares these permissions:

**Classic PAT scopes:**

{{classic_scopes}}

**GitHub App organization permissions** (API names and access levels):

{{app_permissions}}

These requirements apply to Projects synchronization only. Repository access
needed for linking depends on visibility and account permissions; a classic PAT
may also need `repo` for private repositories or `public_repo` for public
repository operations. Grant only what your repository requires.

<details>
<summary>GitHub CLI (Bash)</summary>

### Personal account

1. Create a [classic personal access token](https://github.com/settings/tokens/new)
   on GitHub for a user who can manage the project. Grant the declared classic
   PAT scopes above and any repository access needed for linking.
2. Sign in with `gh auth login`, then run this and paste the token at the prompt:

   ```bash
   gh secret set {{projects_token}} --repo {{repository}}
   ```

GitHub's website is required to create the classic PAT. `gh auth refresh`
changes the CLI's own authorization; it does not set the Actions secret.

### Organization

1. On GitHub, [create or configure an App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app)
   with the declared organization permissions above, install it on the organization,
   and grant it access to the repository where needed. Record its App ID and
   [generate a private key](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps).
2. Replace `YOUR_APP_ID` and `PATH_TO_PRIVATE_KEY.pem` with the App ID and
   downloaded key file, then run:

   ```bash
   gh variable set {{app_id}} --repo {{repository}} --body YOUR_APP_ID
   gh secret set {{app_private_key}} --repo {{repository}} < PATH_TO_PRIVATE_KEY.pem
   ```

Alternatively, set a Projects-capable token as `{{projects_token}}` with the
`gh secret set` command above. App registration and installation use GitHub's
website.

</details>

<details>
<summary>GitHub website</summary>

### Personal account

1. Create a [classic personal access token](https://github.com/settings/tokens/new)
   for a user who can manage the project. Grant the declared classic PAT scopes and any
   repository access needed for linking.
2. Open `{{repository}}` → **Settings → Secrets and variables → Actions → New
   repository secret**. Name it `{{projects_token}}`, paste the token, and save.

### Organization

1. [Create or configure an App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app)
   with the declared organization permissions above, install it on the organization,
   and grant it access to the repository where needed. Record its App ID and
   [generate a private key](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps).
2. Open `{{repository}}` → **Settings → Secrets and variables → Actions**.
   Under **Variables**, add `{{app_id}}` with the App ID. Under **Secrets**,
   add `{{app_private_key}}` with the complete private key.

Alternatively, add a Projects-capable token as the `{{projects_token}}`
repository secret using the personal-account secret steps above.

</details>

For personal Projects, GitHub does not currently support fine-grained PATs.
An existing GitHub App user access token may also be supplied in the Projects
token secret if it has the required access. This pipeline does not create or
refresh user access tokens; an App ID and private key alone do not authorize a
user-owned Project.

Credential names come from `repo/config/github.toml`. Store actual tokens and
private keys in GitHub Secrets, never in TOML or scripts. The built-in
`GITHUB_TOKEN` cannot access account-owned Projects.

The current sync links each project to this repository; GitHub requires the
same owner for that link. The next source push can apply the definitions once
a usable credential is available. Earlier partial operations, if any, may remain.
