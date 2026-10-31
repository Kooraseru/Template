<details open>
<summary>Use a classic PAT — personal account or organization</summary>

{{token_setup}}

</details>

{{organization_setup}}

<details>
<summary>Required permissions and credential rules</summary>

**Classic PAT scopes** (combined for roles sharing this secret):

{{classic_scopes}}

**App organization permissions:**

{{app_permissions}}

Personal-account Projects use the PAT path above. This template's installed-App
Projects path supports organization ownership. The built-in GITHUB_TOKEN cannot
manage account-owned Projects.

Token and key values belong in Actions secrets. Configuration stores their names.

</details>
