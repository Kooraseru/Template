
<div align="center">

# CI Start

</div>

Bootstrap started CI Execution.

| Repository | Source commit | Planned components |
| --- | --- | --- |
| [Kooraseru/Template](https://github.com/Kooraseru/Template) | `06708b0` | 13 |

<p align="center">
  <a href="https://github.com/Kooraseru/Template/actions">
    <img alt="Open this run" src="https://shieldcn.dev/badge/Open_this_run.svg?gradient=60A5FA%2CA78BFA&amp;size=default&amp;logo=github&amp;logoColor=fff&amp;variant=default">
  </a>
  &nbsp;&nbsp;
  <a href="https://github.com/Kooraseru/Template/actions">
    <img alt="Open CI Execution" src="https://shieldcn.dev/badge/Open_CI_Execution.svg?gradient=6366F1%2CC084FC&amp;size=default&amp;logo=githubactions&amp;logoColor=fff&amp;variant=default">
  </a>
</p>

---

<div align="center">

# CI Execution

</div>

> [!CAUTION]
> Skipped components could not report neutral. Review credential setup below.

| Repository | Source commit | Selected components |
| --- | --- | --- |
| [Kooraseru/Template](https://github.com/Kooraseru/Template) | `06708b0` | 13 |

<p align="center">
  <a href="https://github.com/Kooraseru/Template/actions">
    <img alt="Open this run and its artifacts" src="https://shieldcn.dev/badge/Open_this_run_and_its_artifacts.svg?gradient=6366F1%2CC084FC&amp;size=default&amp;logo=githubactions&amp;logoColor=fff&amp;variant=default">
  </a>
  &nbsp;&nbsp;
  <a href="https://github.com/Kooraseru/Template">
    <img alt="Repository" src="https://shieldcn.dev/badge/Repository.svg?gradient=60A5FA%2CA78BFA&amp;size=default&amp;logo=github&amp;logoColor=fff&amp;variant=default">
  </a>
</p>

### Next steps

- [Enable neutral reporting](#response-1)
- [Update credential permissions](#response-2)

### Components

<details>
<summary><strong>build</strong></summary>

| Component | Outcome | Details |
| --- | --- | --- |
| **application** | passed | |
| **packages** | passed | |
| **pages** | passed | |
| **releases** | passed | |

</details>

<details open>
<summary><strong>publish</strong></summary>

| Component | Outcome | Details |
| --- | --- | --- |
| **attestations** | skipped (neutral Check Run failed) | [details 1](#response-1) |
| **branches** | passed | |
| **packages** | skipped (neutral Check Run failed) | [details 1](#response-1) |
| **pages** | skipped (neutral Check Run failed) | [details 1](#response-1) |
| **releases** | passed | |

</details>

<details open>
<summary><strong>repository</strong></summary>

| Component | Outcome | Details |
| --- | --- | --- |
| **branches** | passed | |
| **labels** | skipped (neutral Check Run failed) | [details 1](#response-1) |
| **plan-projects** | passed | |
| **projects** | skipped (neutral Check Run failed) | [details 1](#response-1) |

</details>

### Details and next steps

<a id="response-1"></a>

<details>
<summary><strong>Enable neutral reporting</strong></summary>

<sub>Affected components: publish/attestations, publish/packages, publish/pages, repository/labels, repository/projects</sub>

### Neutral reporting needs attention

CI did not receive the configured App credentials. This does not establish that no App exists on your account. Option 1 connects an App to this repository; Option 2 changes the skip policy without requiring an App.

**Observed result:** App credentials unavailable.

<details open>
<summary>Option 1: Enable neutral reporting</summary>

Choose an App connection method, then save its credentials using one of the methods below. Only credential names belong in configuration. Store the private key in GitHub Actions secrets.

<details>
<summary>Connect an existing App</summary>

1. [Open the owner's Apps](https://github.com/settings/apps) and select the App to connect to this repository.
2. Open **General** and copy its numeric **App ID**.
3. Locate its saved private key. Generate a new key only if you no longer have one.
4. Open **Install App**, select the repository owner's installation, and confirm `Kooraseru/Template` is included.

Set these permissions in **Permissions & events**, then approve any installation permission update:

- Repository: checks = write
- Repository: contents = write
- Repository: workflows = write

</details>

<details>
<summary>Register and connect a new App</summary>

1. [Create the App on your personal account, with fields prefilled](https://github.com/settings/apps/new?name=Kooraseru-Template-CI&description=CI%20automation%20for%20Kooraseru%2FTemplate&url=https%3A%2F%2Fgithub.com%2FKooraseru%2FTemplate&public=false&webhook_active=false&checks=write&contents=write&workflows=write).
2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.

</details>

<details>
<summary>Save credentials with GitHub CLI (Bash)</summary>

5. Run this block. Enter the App ID and the downloaded key's file path when asked:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     read -r -p 'App ID: ' ci_app_id </dev/tty
     read -r -p 'Downloaded .pem path (no surrounding quotes): ' ci_app_key_path </dev/tty

     if [[ "$ci_app_id" =~ ^[0-9]+$ && -f "$ci_app_key_path" ]]; then
       gh variable set CI_APP_ID --repo Kooraseru/Template --body "$ci_app_id" &&
       gh secret set CI_APP_PRIVATE_KEY --repo Kooraseru/Template < "$ci_app_key_path" &&
       gh run list --repo Kooraseru/Template --limit 5
     else
       printf '%s\n' 'Check the App ID and .pem path, then run this block again.'
       exit 1
     fi
   )
   ```

6. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Save credentials on GitHub</summary>

5. [Open repository Actions variables](https://github.com/Kooraseru/Template/settings/variables/actions) → **New repository variable** (or edit the existing variable). Use this **Name**:

   ```text
   CI_APP_ID
   ```

   **Value:** paste the numeric App ID → **Add variable** or **Update variable**.

6. Open the downloaded `.pem` file in a text editor → **Ctrl+A → Ctrl+C**.
7. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions) → **New repository secret** (or edit the existing secret). Use this **Name**:

   ```text
   CI_APP_PRIVATE_KEY
   ```

   **Secret:** paste the copied `.pem` content, including BEGIN/END lines → **Add secret** or **Update secret**.

8. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>

</details>

<details>
<summary>Option 2: Change how CI handles skipped work</summary>

1. [Edit execution settings](https://github.com/Kooraseru/Template/blob/HEAD/repo/config/ci/execution.toml).
2. In `[skip]`, set `default` to one of these values:

   | Value | Result when a component skips |
   | --- | --- |
   | `success` | The reporting job succeeds. The component remains skipped. |
   | `failure` | The reporting job fails. |
   | `neutral` | An authorized App creates a separate neutral Check Run. |

3. Commit to the default branch. The new run uses this setting.

</details>

<details>
<summary>Why this run failed and which permissions are required</summary>

**Required Check Run repository permissions:**

- checks: write

The component skipped. CI then tried to report `neutral`, but could not create the Check Run. The reporting job therefore failed.

A classic PAT cannot create Check Runs. Adding PAT scopes will not fix this operation. The PAT can continue serving other configured CI tasks.

[GitHub Check Run requirements](https://docs.github.com/en/rest/checks/runs#create-a-check-run).

</details>

</details>

<a id="response-2"></a>

<details>
<summary><strong>Update credential permissions</strong></summary>

<sub>Affected components: bootstrap</sub>

**Credential: CI_PROJECTS_TOKEN**

GitHub rejected the credential with HTTP 401. It may be expired, revoked, or invalid. Renew or replace it, then update its named Actions secret.

<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new?description=CI_PROJECTS_TOKEN%20-%20CI%20for%20Kooraseru%2FTemplate&scopes=repo%2Cworkflow%2Cproject).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_PROJECTS_TOKEN --repo Kooraseru/Template &&
     gh run list --repo Kooraseru/Template --limit 5
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_PROJECTS_TOKEN`.
2. Under **Select scopes**, enable: `repo`, `workflow`, `project`.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run list --repo Kooraseru/Template --limit 5
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new?description=CI_PROJECTS_TOKEN%20-%20CI%20for%20Kooraseru%2FTemplate&scopes=repo%2Cworkflow%2Cproject).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
4. Click the pencil beside `CI_PROJECTS_TOKEN`. If it is absent, click **New repository secret** and use this name:

   ```text
   CI_PROJECTS_TOKEN
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>

</details>
