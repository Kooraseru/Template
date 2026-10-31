<details open>
<summary>GitHub CLI — guided prompts</summary>

{{app_registration}}

5. Run this block. Enter the App ID and the downloaded key's file path when asked:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     read -r -p 'App ID: ' ci_app_id </dev/tty
     read -r -p 'Downloaded .pem path (no surrounding quotes): ' ci_app_key_path </dev/tty
     if [[ "$ci_app_id" =~ ^[0-9]+$ && -f "$ci_app_key_path" ]]; then
       gh variable set {{app_id}} --repo {{repository}} --body "$ci_app_id" &&
       gh secret set {{app_private_key}} --repo {{repository}} < "$ci_app_key_path" &&
       {{retry_command}}
     else
       printf '%s\n' 'Check the App ID and .pem path, then run this block again.'
       exit 1
     fi
   )
   ```

6. [Open the run]({{actions_url}}).

</details>

<details>
<summary>GitHub website — click by click</summary>

{{app_registration}}

5. [Open repository Actions variables]({{variables_url}}) → **New repository variable** (or edit the existing variable). Use this **Name**:

   ```text
   {{app_id}}
   ```

   **Value:** paste the numeric App ID → **Add variable** or **Update variable**.

6. Open the downloaded `.pem` file in a text editor → **Ctrl+A → Ctrl+C**.
7. [Open repository Actions secrets]({{secrets_url}}) → **New repository secret** (or edit the existing secret). Use this **Name**:

   ```text
   {{app_private_key}}
   ```

   **Secret:** paste the copied `.pem` content, including BEGIN/END lines → **Add secret** or **Update secret**.

8. [Open the run]({{actions_url}}) → **Re-run jobs → Re-run failed jobs**.

</details>

<details>
<summary>Already have an App? Update it</summary>

1. [Open your Apps]({{apps_url}}) → select the App → **Permissions & events**.
2. Set the required permissions shown in this warning → **Save changes**.

   {{app_registration_permissions}}

3. Open **Install App** → the owner's installation → approve the permission update if requested.
4. If the App ID or key changed, use either setup method above to update its stored credentials. Otherwise, [open the run]({{actions_url}}) → **Re-run jobs → Re-run failed jobs**.

</details>
