## Credential permissions: {{credential}}

{{permission_evidence}}

<details>
<summary>GitHub CLI (Bash)</summary>

Update the token's permissions in GitHub, or [create its replacement]({{token_url}}).
Then update the named Actions secret; paste the value at the prompt:

```bash
gh secret set {{credential}} --repo {{repository}}
```

</details>

<details>
<summary>GitHub website</summary>

Open **Settings → Developer settings → Personal access tokens** to edit or
replace the credential. Then open `{{repository}}` → **Settings → Secrets and
variables → Actions**, and update `{{credential}}`.

</details>

Fine-grained PAT and App permissions cannot be inferred from classic scope
headers. A successful scope check also does not prove access to every resource.
Configuration stores secret names; credential values belong only in GitHub Secrets.
