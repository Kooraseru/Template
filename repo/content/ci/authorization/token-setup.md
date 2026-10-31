<details open>
<summary>GitHub CLI — copy/paste</summary>

1. [Create the token with its name and scopes prefilled]({{token_url}}).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set {{credential}} --repo {{repository}} &&
     {{retry_command}}
   )
   ```

4. [Open the run]({{actions_url}}).

</details>

<details>
<summary>Keep the existing token — edit its scopes</summary>

1. [Open classic tokens]({{tokens_url}}) → select the token whose Note identifies `{{credential}}`.
2. Under **Select scopes**, enable: {{required_scopes}}.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   {{retry_command}}
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website — click by click</summary>

1. [Create the token with its name and scopes prefilled]({{token_url}}).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets]({{secrets_url}}).
4. Click the pencil beside `{{credential}}`. If it is absent, click **New repository secret** and use this name:

   ```text
   {{credential}}
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run]({{actions_url}}) → **Re-run jobs → Re-run failed jobs**.

</details>
