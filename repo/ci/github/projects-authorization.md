## Projects authorization required

Project synchronization for **{{owner}}** was skipped, not completed.

- Organization App: install it for the target organization and grant
  **Organization Projects: read/write**. Configure App ID `{{app_id}}` and
  private-key secret `{{app_private_key}}`.
- Alternatively, create the GitHub secret named `{{projects_token}}` containing
  a Projects-capable App installation/user token or PAT. A classic PAT needs
  `project` scope, plus access to the linked repository where required.
- Put credential **names** in `repo/config/github.toml`. Actual private keys and
  tokens belong in GitHub Secrets, never source files.

The repository's built-in `GITHUB_TOKEN` cannot access account-owned Projects.
Once the configured credential is available, the next source push can apply the
project blueprints automatically. Earlier partial operations, if any, may remain.

