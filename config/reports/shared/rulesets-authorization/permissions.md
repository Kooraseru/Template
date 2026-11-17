**Sync result:** {{state}}

**Observed result:** {{diagnostic}}

| Credential | Required access |
| --- | --- |
| Configured GitHub App | Repository **Administration: Read and write**, approved on the installation |
| Secret `{{token_name}}` | Fine-grained PAT **Administration: Read and write** for this repository, or a classic PAT with `repo` scope and administrative repository access |

## Next steps

1. Open the GitHub App's **Permissions & events** and grant repository **Administration: Read and write**, then approve the installation's permission update.
2. Alternatively, configure `{{token_name}}` as a repository Actions secret with the required access.
3. If the API returned **HTTP 422**, authentication succeeded far enough to submit a ruleset change. Inspect the API validation message and the source ruleset configuration; changing credentials alone will not resolve an invalid payload.

[GitHub ruleset API permissions and validation](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)
