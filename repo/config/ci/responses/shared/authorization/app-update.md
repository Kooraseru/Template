<details open>
<summary>Update the configured App on GitHub</summary>

1. [Open the owner's Apps]({{apps_url}}). Select the App whose ID matches `{{app_id}}` in [Actions variables]({{variables_url}}) or [Actions secrets]({{secrets_url}}).
2. Open **Permissions & events**. Apply these requirements:

   {{app_registration_permissions}}

3. Click **Save changes**.
4. Open **Install App**. Select the repository owner's installation, include `{{repository}}`, and approve any pending permission request.
5. For an authentication rejection, verify the stored App ID and private key belong to the same App. Replace `{{app_private_key}}` in [Actions secrets]({{secrets_url}}) if its key was revoked.

<details>
<summary>Retry with GitHub CLI (Bash)</summary>

```bash
{{retry_command}}
```

</details>

<details>
<summary>Retry on GitHub</summary>

[Open the run]({{actions_url}}). Click **Re-run jobs**, then **Re-run failed jobs**.

</details>

</details>
