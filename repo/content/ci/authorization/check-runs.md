## Check Run authorization: {{status}}

The component **{{component}}** skipped, but its configured `neutral` reporting
could not create the separate Check Run. This failure concerns Check Run
reporting; it does not establish a Projects synchronization failure.

This reporting backend uses the App ID named `{{app_id}}` and private-key secret
named `{{app_private_key}}` from `repo/config/github.toml`.

**Required App repository permissions:**

{{app_permissions}}

<details>
<summary>GitHub CLI (Bash)</summary>

Configure the App's permissions and approve the installation update on GitHub.
If its credentials changed, update the configured names:

```bash
gh variable set {{app_id}} --repo {{repository}} --body YOUR_APP_ID
gh secret set {{app_private_key}} --repo {{repository}} < PATH_TO_PRIVATE_KEY.pem
```

</details>

<details>
<summary>GitHub website</summary>

Open the App's **Permissions & events** settings, grant the permissions above,
and approve any requested installation update for `{{repository}}`.
Under the repository's **Settings → Secrets and variables → Actions**, configure
the App ID variable and private-key secret using the names above.

</details>

No neutral Check Run was created. Component execution remains skipped; the
configured reporting policy still determines the job's failure. Existing PAT
credentials are not used by this App-backed reporting implementation.
