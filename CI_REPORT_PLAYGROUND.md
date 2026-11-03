# CI report Markdown playground

This file is a format workshop. It renders real GitHub Markdown and supported HTML using **filled synthetic CI data**. Nothing here is connected to a live run, and no production response templates are changed.

> [!NOTE]
> The fixtures intentionally include mutually exclusive success, failure, and credential states. They are all shown together to test rendering, not to describe an actual run.

| Preview | Pattern | Comparison |
| --- | --- | --- |
| [A. Complete start and execution reports](#a-complete-start-and-execution-reports) | Nested component tree, separate attachment table | Current architecture with a unified row format |
| [B. One unified table](#b-one-unified-table) | Groups, components, and attachments in one three-column table | Scannability and compactness |
| [C. Components own their attachments](#c-components-own-their-attachments) | Collapsible component cards containing full attachment details | Deep nesting and local context |
| [All 38 response templates](#all-38-response-templates) | Every existing template filled with example values | Complete template and nested-detail coverage |

**Default test settings**

| Property | Value |
| --- | --- |
| Columns | `Component/Attachment` / `Outcome` / `Additional Notes` |
| Badge size | Shieldcn `default` |
| Badge style | `branded`, shared white text |
| Badge geometry | Provider-managed, no HTML `height` or `width` |
| Data | 13 component outcomes, 11 attachment types, permission and error variants |
| Branch behavior | This Markdown is standalone; it is not registered in `responses.toml` |

---

## A. Complete start and execution reports

<details open>
<summary><strong>Open full reports with nested component groups and all attachments</strong></summary>

<div align="center">
<h1>CI Start</h1>

<p align="center"><img alt="success" src="https://shieldcn.dev/badge/success.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></p>

<p align="center">Bootstrap accepted the source commit and prepared 13 component checks.</p>

<table align="center">
<thead><tr><th align="center">Repository</th><th align="center">Source commit</th><th align="center">Planned components</th></tr></thead>
<tbody><tr><td align="center"><a href="https://github.com/Kooraseru/Template">Kooraseru/Template</a></td><td align="center"><code>bb828e2</code></td><td align="center">13</td></tr></tbody>
</table>

<p align="center"><a href="https://github.com/Kooraseru/Template/actions"><img alt="Open this run" src="https://shieldcn.dev/badge/Open_this_run.svg?variant=branded&amp;size=default&amp;color=5385B1&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a>&nbsp;&nbsp;<a href="https://github.com/Kooraseru/Template/actions"><img alt="Open CI Execution" src="https://shieldcn.dev/badge/Open_CI_Execution.svg?variant=branded&amp;size=default&amp;color=8B75B5&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=githubactions"></a></p>


### Next steps

<p align="center"><a href="#a-start-token-permissions"><img alt="Update credential permissions" src="https://shieldcn.dev/badge/Update_credential_permissions.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a> <a href="#a-start-app-connect"><img alt="App connection" src="https://shieldcn.dev/badge/App_connection.svg?variant=branded&amp;size=default&amp;color=5385B1&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a></p>


## Components

<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>bootstrap</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>auth</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Credential and source checks complete · <a href="#a-start-token-permissions">Update credential permissions</a> · <a href="#a-start-app-connect">Connect or register a GitHub App</a> · <a href="#a-start-app-update">Update App installation permissions</a> · <a href="#a-start-app-restore">Restore existing App credentials</a></td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>



<h2>Details and next steps</h2>
<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><a id="a-start-token-permissions"></a><details><summary><strong>Update credential permissions</strong></summary>

**Credential: CI_WORKFLOW_TOKEN**

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, workflow

**Missing scopes:** workflow

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_WORKFLOW_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_WORKFLOW_TOKEN`.
2. Under **Select scopes**, enable: repo, workflow.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
4. Click the pencil beside `CI_WORKFLOW_TOKEN`. If it is absent, click **New repository secret** and use this name:

   ```text
   CI_WORKFLOW_TOKEN
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>



</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code>, <code>releases/publish</code></td></tr>
<tr><td align="center"><a id="a-start-app-connect"></a><details><summary><strong>Connect or register a GitHub App</strong></summary>

Choose an App connection method, then save its credentials using one of the
methods below. Only credential names belong in configuration. Store the private
key in GitHub Actions secrets.

<details>
<summary>Connect an existing App</summary>

Open your existing App under GitHub Settings, verify the App ID and private key, then confirm Kooraseru/Template is installed.

Set these permissions in **Permissions & events**, then approve any installation
permission update:

Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

</details>

<details>
<summary>Register and connect a new App</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


</details>


</details></td><td align="center"><img alt="info" src="https://shieldcn.dev/badge/info.svg?variant=branded&amp;size=default&amp;color=5385B1&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code></td></tr>
<tr><td align="center"><a id="a-start-app-update"></a><details><summary><strong>Update App installation permissions</strong></summary>

<details open>
<summary>Update the configured App on GitHub</summary>

1. [Open the owner's Apps](https://github.com/settings/apps). Select the App whose ID matches `CI_APP_ID` in [Actions variables](https://github.com/Kooraseru/Template/settings/variables/actions) or [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
2. Open **Permissions & events**. Apply these requirements:

   Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

3. Click **Save changes**.
4. Open **Install App**. Select the repository owner's installation, include `Kooraseru/Template`, and approve any pending permission request.
5. For an authentication rejection, verify the stored App ID and private key belong to the same App. Replace `CI_APP_PRIVATE_KEY` in [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions) if its key was revoked.

<details>
<summary>Retry with GitHub CLI (Bash)</summary>

```bash
gh run rerun 41562908008 --failed --repo Kooraseru/Template
```

</details>

<details>
<summary>Retry on GitHub</summary>

[Open the run](https://github.com/Kooraseru/Template/actions). Click **Re-run jobs**, then **Re-run failed jobs**.

</details>

</details>


</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code></td></tr>
<tr><td align="center"><a id="a-start-app-restore"></a><details><summary><strong>Restore existing App credentials</strong></summary>

1. [Open the owner's Apps](https://github.com/settings/apps) and select the App to connect to this repository.
2. Open **General** and copy its numeric **App ID**.
3. Locate its saved private key. Generate a new key only if you no longer have one.
4. Open **Install App**, select the repository owner's installation, and confirm `Kooraseru/Template` is included.


</details></td><td align="center"><img alt="neutral" src="https://shieldcn.dev/badge/neutral.svg?variant=branded&amp;size=default&amp;color=64748B&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code></td></tr>
</tbody></table>

</div>


<hr>

<div align="center">
<h1>CI Execution</h1>

<p align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></p>

<p align="center">7 passed, 3 failed, 1 blocked, 1 pending, 1 skipped (synthetic fixture).</p>

<table align="center">
<thead><tr><th align="center">Repository</th><th align="center">Source commit</th><th align="center">Selected components</th></tr></thead>
<tbody><tr><td align="center"><a href="https://github.com/Kooraseru/Template">Kooraseru/Template</a></td><td align="center"><code>bb828e2</code></td><td align="center">13</td></tr></tbody>
</table>

<p align="center"><a href="https://github.com/Kooraseru/Template/actions"><img alt="Open this run and its artifacts" src="https://shieldcn.dev/badge/Open_this_run_and_its_artifacts.svg?variant=branded&amp;size=default&amp;color=8B75B5&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=githubactions"></a>&nbsp;&nbsp;<a href="https://github.com/Kooraseru/Template"><img alt="Repository" src="https://shieldcn.dev/badge/Repository.svg?variant=branded&amp;size=default&amp;color=5385B1&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a></p>


### Next steps

<p align="center"><a href="#a-exec-ruleset-diagnostic"><img alt="Ruleset API diagnostic" src="https://shieldcn.dev/badge/Ruleset_API_diagnostic.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a> <a href="#a-exec-projects-missing"><img alt="Projects access" src="https://shieldcn.dev/badge/Projects_access.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a> <a href="#a-exec-neutral-reporting"><img alt="Neutral reporting" src="https://shieldcn.dev/badge/Neutral_reporting.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a></p>


## Components

<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>bootstrap</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>auth</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Credential and source checks complete · <a href="#a-exec-token-permissions">Update credential permissions</a> · <a href="#a-exec-app-connect">Connect or register a GitHub App</a> · <a href="#a-exec-app-update">Update App installation permissions</a> · <a href="#a-exec-app-restore">Restore existing App credentials</a></td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>


<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>application</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>lint</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Luau and Bash style checks</td></tr>
</tbody></table>

<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>build</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>client</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Build artifacts: 3</td></tr>
<tr><td align="center"><strong>server</strong></td><td align="center"><img alt="failed" src="https://shieldcn.dev/badge/failed.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Native dependency compilation failed · <a href="#a-exec-execution-error">Execution stopped</a></td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>


</details>
</th>
</tr>
</thead>
</table>


<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>branches</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>protect</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Protected branch: source · <a href="#a-exec-ruleset-diagnostic">Ruleset permissions and API diagnostic</a></td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>


<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>labels</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>sync</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>8 labels verified</td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>


<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>packages</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>build</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Package archive generated</td></tr>
<tr><td align="center"><strong>publish</strong></td><td align="center"><img alt="skipped" src="https://shieldcn.dev/badge/skipped.svg?variant=branded&amp;size=default&amp;color=64748B&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Separate Check Run: neutral · <a href="#a-exec-neutral-reporting">Enable neutral reporting</a></td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>


<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>pages</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>deploy</strong></td><td align="center"><img alt="pending" src="https://shieldcn.dev/badge/pending.svg?variant=branded&amp;size=default&amp;color=8B75B5&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Awaiting deployment environment</td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>


<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>projects</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>sync</strong></td><td align="center"><img alt="blocked" src="https://shieldcn.dev/badge/blocked.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>CI_PROJECTS_TOKEN requires project scope · <a href="#a-exec-projects-missing">Projects: credential needed</a> · <a href="#a-exec-projects-insufficient">Projects: update credential access</a></td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>


<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>releases</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>publish</strong></td><td align="center"><img alt="failed" src="https://shieldcn.dev/badge/failed.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Release gate rejected publish · <a href="#a-exec-token-permissions">Update credential permissions</a> · <a href="#a-exec-response-transfer">Some response details are unavailable</a></td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>


<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>rulesets</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>sync</strong></td><td align="center"><img alt="failed" src="https://shieldcn.dev/badge/failed.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>HTTP 422: invalid API body · <a href="#a-exec-ruleset-diagnostic">Ruleset permissions and API diagnostic</a></td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>


<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>attestations</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><strong>publish</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Build provenance statement uploaded · <a href="#a-exec-artifact-provenance">Artifact provenance</a></td></tr>
</tbody></table>



</details>
</th>
</tr>
</thead>
</table>



<h2>Details and next steps</h2>
<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td align="center"><a id="a-exec-artifact-provenance"></a><details><summary><strong>Artifact provenance</strong></summary>

## Artifact attestations

| Feature | Outcome |
| --- | --- |
| Build provenance | <img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"> |

The generated build artifact contains a verifiable provenance statement.



</details></td><td align="center"><img alt="success" src="https://shieldcn.dev/badge/success.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>attestations/publish</code></td></tr>
<tr><td align="center"><a id="a-exec-neutral-reporting"></a><details><summary><strong>Enable neutral reporting</strong></summary>

CI received the configured App ID and private key, but GitHub rejected the
operation. Update that App's installation or permissions using Option 1.
Credential presence alone does not establish that its permissions are sufficient.


**Observed result:** Neutral Check Run could not be created (HTTP 403).

<details open>
<summary>Option 1: Enable neutral reporting</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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

1. [Edit execution settings](https://github.com/Kooraseru/Template/blob/source/repo/config/ci/execution.toml).
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

Repository Checks: Read and write; installed on Kooraseru/Template

The component skipped. CI then tried to report `neutral`, but could not create
the Check Run. The reporting job therefore failed.

A classic PAT cannot create Check Runs. Adding PAT scopes will not fix this
operation. The PAT can continue serving other configured CI tasks.

[GitHub Check Run requirements](https://docs.github.com/en/rest/checks/runs#create-a-check-run).

</details>


</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>packages/publish</code></td></tr>
<tr><td align="center"><a id="a-exec-token-permissions"></a><details><summary><strong>Update credential permissions</strong></summary>

**Credential: CI_WORKFLOW_TOKEN**

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, workflow

**Missing scopes:** workflow

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_WORKFLOW_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_WORKFLOW_TOKEN`.
2. Under **Select scopes**, enable: repo, workflow.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
4. Click the pencil beside `CI_WORKFLOW_TOKEN`. If it is absent, click **New repository secret** and use this name:

   ```text
   CI_WORKFLOW_TOKEN
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>



</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code>, <code>releases/publish</code></td></tr>
<tr><td align="center"><a id="a-exec-ruleset-diagnostic"></a><details><summary><strong>Ruleset permissions and API diagnostic</strong></summary>

**Sync result:** Failed: GitHub rejected the ruleset operation

| Credential | Required access |
| --- | --- |
| Configured GitHub App | Repository **Administration: Read and write**, approved on the installation |
| Secret `CI_RULESETS_TOKEN` | Fine-grained PAT **Administration: Read and write** for this repository, or a classic PAT with `repo` scope and administrative repository access |

<details>
<summary>Show permissions, API diagnostic, and next steps</summary>

**Observed result:** Rulesets API PUT failed (HTTP 422): /bypass_actors and /conditions/ref_name/exclude must be arrays.

1. Open the GitHub App's **Permissions & events** and grant repository **Administration: Read and write**, then approve the installation's permission update.
2. Alternatively, configure `CI_RULESETS_TOKEN` as a repository Actions secret with the required access.
3. If the API returned **HTTP 422**, authentication succeeded far enough to submit a ruleset change. Inspect the API validation message and the source TOML rule parameters; changing credentials alone will not resolve an invalid payload.

[GitHub ruleset API permissions and validation](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)

</details>


</details></td><td align="center"><img alt="failure" src="https://shieldcn.dev/badge/failure.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>rulesets/sync</code>, <code>branches/protect</code></td></tr>
<tr><td align="center"><a id="a-exec-projects-missing"></a><details><summary><strong>Projects: credential needed</strong></summary>

## Projects: credential needed

Configure `CI_PROJECTS_TOKEN` to manage Projects owned by **Kooraseru**.
Choose a method below.

<details open>
<summary>Use a classic PAT - personal account or organization</summary>

<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_PROJECTS_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_PROJECTS_TOKEN`.
2. Under **Select scopes**, enable: repo, project, read:org.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
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

<details>
<summary>Use a GitHub App - organization-owned Projects only</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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
<summary>Required permissions and credential rules</summary>

**Classic PAT scopes** (combined for roles sharing this secret):

repo, project, read:org

**App organization permissions:**

Repository Checks: Read and write; installed on Kooraseru/Template

Personal-account Projects use the PAT path above. This template's installed-App
Projects path supports organization ownership. The built-in GITHUB_TOKEN cannot
manage account-owned Projects.

Token and key values belong in Actions secrets. Configuration stores their names.

</details>


</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>projects/sync</code></td></tr>
<tr><td align="center"><a id="a-exec-projects-insufficient"></a><details><summary><strong>Projects: update credential access</strong></summary>

## Projects: update credential access

The supplied credential could not authorize Projects synchronization for
**Kooraseru**. Update `CI_PROJECTS_TOKEN` or the configured App below.

<details>
<summary>Show the permission check result</summary>

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, project

**Missing scopes:** project

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


Synchronization was skipped; earlier partial changes may remain.

</details>

<details open>
<summary>Use a classic PAT - personal account or organization</summary>

<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_PROJECTS_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_PROJECTS_TOKEN`.
2. Under **Select scopes**, enable: repo, project, read:org.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
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

<details>
<summary>Use a GitHub App - organization-owned Projects only</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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
<summary>Required permissions and credential rules</summary>

**Classic PAT scopes** (combined for roles sharing this secret):

repo, project, read:org

**App organization permissions:**

Repository Checks: Read and write; installed on Kooraseru/Template

Personal-account Projects use the PAT path above. This template's installed-App
Projects path supports organization ownership. The built-in GITHUB_TOKEN cannot
manage account-owned Projects.

Token and key values belong in Actions secrets. Configuration stores their names.

</details>


</details></td><td align="center"><img alt="failure" src="https://shieldcn.dev/badge/failure.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>projects/sync</code></td></tr>
<tr><td align="center"><a id="a-exec-app-connect"></a><details><summary><strong>Connect or register a GitHub App</strong></summary>

Choose an App connection method, then save its credentials using one of the
methods below. Only credential names belong in configuration. Store the private
key in GitHub Actions secrets.

<details>
<summary>Connect an existing App</summary>

Open your existing App under GitHub Settings, verify the App ID and private key, then confirm Kooraseru/Template is installed.

Set these permissions in **Permissions & events**, then approve any installation
permission update:

Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

</details>

<details>
<summary>Register and connect a new App</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


</details>


</details></td><td align="center"><img alt="info" src="https://shieldcn.dev/badge/info.svg?variant=branded&amp;size=default&amp;color=5385B1&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code></td></tr>
<tr><td align="center"><a id="a-exec-app-update"></a><details><summary><strong>Update App installation permissions</strong></summary>

<details open>
<summary>Update the configured App on GitHub</summary>

1. [Open the owner's Apps](https://github.com/settings/apps). Select the App whose ID matches `CI_APP_ID` in [Actions variables](https://github.com/Kooraseru/Template/settings/variables/actions) or [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
2. Open **Permissions & events**. Apply these requirements:

   Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

3. Click **Save changes**.
4. Open **Install App**. Select the repository owner's installation, include `Kooraseru/Template`, and approve any pending permission request.
5. For an authentication rejection, verify the stored App ID and private key belong to the same App. Replace `CI_APP_PRIVATE_KEY` in [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions) if its key was revoked.

<details>
<summary>Retry with GitHub CLI (Bash)</summary>

```bash
gh run rerun 41562908008 --failed --repo Kooraseru/Template
```

</details>

<details>
<summary>Retry on GitHub</summary>

[Open the run](https://github.com/Kooraseru/Template/actions). Click **Re-run jobs**, then **Re-run failed jobs**.

</details>

</details>


</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code></td></tr>
<tr><td align="center"><a id="a-exec-app-restore"></a><details><summary><strong>Restore existing App credentials</strong></summary>

1. [Open the owner's Apps](https://github.com/settings/apps) and select the App to connect to this repository.
2. Open **General** and copy its numeric **App ID**.
3. Locate its saved private key. Generate a new key only if you no longer have one.
4. Open **Install App**, select the repository owner's installation, and confirm `Kooraseru/Template` is included.


</details></td><td align="center"><img alt="neutral" src="https://shieldcn.dev/badge/neutral.svg?variant=branded&amp;size=default&amp;color=64748B&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code></td></tr>
<tr><td align="center"><a id="a-exec-execution-error"></a><details><summary><strong>Execution stopped</strong></summary>

CI stopped before it could complete this operation. Open the run logs for the reported error. Unfinished work is not reported as completed.

</details></td><td align="center"><img alt="failure" src="https://shieldcn.dev/badge/failure.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>application/build/server</code></td></tr>
<tr><td align="center"><a id="a-exec-response-transfer"></a><details><summary><strong>Some response details are unavailable</strong></summary>

Some component response fragments could not be downloaded. The component job outcomes are still shown. Open the affected jobs' logs for missing details. Unavailable fragments are not treated as evidence that an operation succeeded.

</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>releases/publish</code></td></tr>
</tbody></table>

</div>


</details>

---

## B. One unified table

<details>
<summary><strong>Open full three-column report</strong></summary>

<h1 align="center">CI Execution</h1>
<p align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></p>
<p align="center">The same 13 components and every attachment in one report table.</p>
<p align="center"><a href="https://github.com/Kooraseru/Template/actions"><img alt="Open this run" src="https://shieldcn.dev/badge/Open_this_run.svg?variant=branded&amp;size=default&amp;color=5385B1&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a> <a href="https://github.com/Kooraseru/Template/actions"><img alt="View artifacts" src="https://shieldcn.dev/badge/View_artifacts.svg?variant=branded&amp;size=default&amp;color=8B75B5&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=githubactions"></a></p>
<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><th align="left" colspan="3">bootstrap</th></tr>
<tr><td><code>bootstrap/auth</code></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Credential and source checks complete · <a href="#b-token-permissions">Update credential permissions</a> · <a href="#b-app-connect">Connect or register a GitHub App</a> · <a href="#b-app-update">Update App installation permissions</a> · <a href="#b-app-restore">Restore existing App credentials</a></td></tr>
<tr><th align="left" colspan="3">application</th></tr>
<tr><td><code>application/lint</code></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Luau and Bash style checks</td></tr>
<tr><td><code>application/build/client</code></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Build artifacts: 3</td></tr>
<tr><td><code>application/build/server</code></td><td align="center"><img alt="failed" src="https://shieldcn.dev/badge/failed.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Native dependency compilation failed · <a href="#b-execution-error">Execution stopped</a></td></tr>
<tr><th align="left" colspan="3">branches</th></tr>
<tr><td><code>branches/protect</code></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Protected branch: source · <a href="#b-ruleset-diagnostic">Ruleset permissions and API diagnostic</a></td></tr>
<tr><th align="left" colspan="3">labels</th></tr>
<tr><td><code>labels/sync</code></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>8 labels verified</td></tr>
<tr><th align="left" colspan="3">packages</th></tr>
<tr><td><code>packages/build</code></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Package archive generated</td></tr>
<tr><td><code>packages/publish</code></td><td align="center"><img alt="skipped" src="https://shieldcn.dev/badge/skipped.svg?variant=branded&amp;size=default&amp;color=64748B&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Separate Check Run: neutral · <a href="#b-neutral-reporting">Enable neutral reporting</a></td></tr>
<tr><th align="left" colspan="3">pages</th></tr>
<tr><td><code>pages/deploy</code></td><td align="center"><img alt="pending" src="https://shieldcn.dev/badge/pending.svg?variant=branded&amp;size=default&amp;color=8B75B5&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Awaiting deployment environment</td></tr>
<tr><th align="left" colspan="3">projects</th></tr>
<tr><td><code>projects/sync</code></td><td align="center"><img alt="blocked" src="https://shieldcn.dev/badge/blocked.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>CI_PROJECTS_TOKEN requires project scope · <a href="#b-projects-missing">Projects: credential needed</a> · <a href="#b-projects-insufficient">Projects: update credential access</a></td></tr>
<tr><th align="left" colspan="3">releases</th></tr>
<tr><td><code>releases/publish</code></td><td align="center"><img alt="failed" src="https://shieldcn.dev/badge/failed.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Release gate rejected publish · <a href="#b-token-permissions">Update credential permissions</a> · <a href="#b-response-transfer">Some response details are unavailable</a></td></tr>
<tr><th align="left" colspan="3">rulesets</th></tr>
<tr><td><code>rulesets/sync</code></td><td align="center"><img alt="failed" src="https://shieldcn.dev/badge/failed.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>HTTP 422: invalid API body · <a href="#b-ruleset-diagnostic">Ruleset permissions and API diagnostic</a></td></tr>
<tr><th align="left" colspan="3">attestations</th></tr>
<tr><td><code>attestations/publish</code></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Build provenance statement uploaded · <a href="#b-artifact-provenance">Artifact provenance</a></td></tr>
<tr><th align="left" colspan="3">All attachments</th></tr>
<tr><td align="center"><a id="b-artifact-provenance"></a><details><summary><strong>Artifact provenance</strong></summary>

## Artifact attestations

| Feature | Outcome |
| --- | --- |
| Build provenance | <img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"> |

The generated build artifact contains a verifiable provenance statement.



</details></td><td align="center"><img alt="success" src="https://shieldcn.dev/badge/success.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>attestations/publish</code></td></tr>
<tr><td align="center"><a id="b-neutral-reporting"></a><details><summary><strong>Enable neutral reporting</strong></summary>

CI received the configured App ID and private key, but GitHub rejected the
operation. Update that App's installation or permissions using Option 1.
Credential presence alone does not establish that its permissions are sufficient.


**Observed result:** Neutral Check Run could not be created (HTTP 403).

<details open>
<summary>Option 1: Enable neutral reporting</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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

1. [Edit execution settings](https://github.com/Kooraseru/Template/blob/source/repo/config/ci/execution.toml).
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

Repository Checks: Read and write; installed on Kooraseru/Template

The component skipped. CI then tried to report `neutral`, but could not create
the Check Run. The reporting job therefore failed.

A classic PAT cannot create Check Runs. Adding PAT scopes will not fix this
operation. The PAT can continue serving other configured CI tasks.

[GitHub Check Run requirements](https://docs.github.com/en/rest/checks/runs#create-a-check-run).

</details>


</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>packages/publish</code></td></tr>
<tr><td align="center"><a id="b-token-permissions"></a><details><summary><strong>Update credential permissions</strong></summary>

**Credential: CI_WORKFLOW_TOKEN**

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, workflow

**Missing scopes:** workflow

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_WORKFLOW_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_WORKFLOW_TOKEN`.
2. Under **Select scopes**, enable: repo, workflow.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
4. Click the pencil beside `CI_WORKFLOW_TOKEN`. If it is absent, click **New repository secret** and use this name:

   ```text
   CI_WORKFLOW_TOKEN
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>



</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code>, <code>releases/publish</code></td></tr>
<tr><td align="center"><a id="b-ruleset-diagnostic"></a><details><summary><strong>Ruleset permissions and API diagnostic</strong></summary>

**Sync result:** Failed: GitHub rejected the ruleset operation

| Credential | Required access |
| --- | --- |
| Configured GitHub App | Repository **Administration: Read and write**, approved on the installation |
| Secret `CI_RULESETS_TOKEN` | Fine-grained PAT **Administration: Read and write** for this repository, or a classic PAT with `repo` scope and administrative repository access |

<details>
<summary>Show permissions, API diagnostic, and next steps</summary>

**Observed result:** Rulesets API PUT failed (HTTP 422): /bypass_actors and /conditions/ref_name/exclude must be arrays.

1. Open the GitHub App's **Permissions & events** and grant repository **Administration: Read and write**, then approve the installation's permission update.
2. Alternatively, configure `CI_RULESETS_TOKEN` as a repository Actions secret with the required access.
3. If the API returned **HTTP 422**, authentication succeeded far enough to submit a ruleset change. Inspect the API validation message and the source TOML rule parameters; changing credentials alone will not resolve an invalid payload.

[GitHub ruleset API permissions and validation](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)

</details>


</details></td><td align="center"><img alt="failure" src="https://shieldcn.dev/badge/failure.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>rulesets/sync</code>, <code>branches/protect</code></td></tr>
<tr><td align="center"><a id="b-projects-missing"></a><details><summary><strong>Projects: credential needed</strong></summary>

## Projects: credential needed

Configure `CI_PROJECTS_TOKEN` to manage Projects owned by **Kooraseru**.
Choose a method below.

<details open>
<summary>Use a classic PAT - personal account or organization</summary>

<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_PROJECTS_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_PROJECTS_TOKEN`.
2. Under **Select scopes**, enable: repo, project, read:org.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
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

<details>
<summary>Use a GitHub App - organization-owned Projects only</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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
<summary>Required permissions and credential rules</summary>

**Classic PAT scopes** (combined for roles sharing this secret):

repo, project, read:org

**App organization permissions:**

Repository Checks: Read and write; installed on Kooraseru/Template

Personal-account Projects use the PAT path above. This template's installed-App
Projects path supports organization ownership. The built-in GITHUB_TOKEN cannot
manage account-owned Projects.

Token and key values belong in Actions secrets. Configuration stores their names.

</details>


</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>projects/sync</code></td></tr>
<tr><td align="center"><a id="b-projects-insufficient"></a><details><summary><strong>Projects: update credential access</strong></summary>

## Projects: update credential access

The supplied credential could not authorize Projects synchronization for
**Kooraseru**. Update `CI_PROJECTS_TOKEN` or the configured App below.

<details>
<summary>Show the permission check result</summary>

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, project

**Missing scopes:** project

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


Synchronization was skipped; earlier partial changes may remain.

</details>

<details open>
<summary>Use a classic PAT - personal account or organization</summary>

<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_PROJECTS_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_PROJECTS_TOKEN`.
2. Under **Select scopes**, enable: repo, project, read:org.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
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

<details>
<summary>Use a GitHub App - organization-owned Projects only</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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
<summary>Required permissions and credential rules</summary>

**Classic PAT scopes** (combined for roles sharing this secret):

repo, project, read:org

**App organization permissions:**

Repository Checks: Read and write; installed on Kooraseru/Template

Personal-account Projects use the PAT path above. This template's installed-App
Projects path supports organization ownership. The built-in GITHUB_TOKEN cannot
manage account-owned Projects.

Token and key values belong in Actions secrets. Configuration stores their names.

</details>


</details></td><td align="center"><img alt="failure" src="https://shieldcn.dev/badge/failure.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>projects/sync</code></td></tr>
<tr><td align="center"><a id="b-app-connect"></a><details><summary><strong>Connect or register a GitHub App</strong></summary>

Choose an App connection method, then save its credentials using one of the
methods below. Only credential names belong in configuration. Store the private
key in GitHub Actions secrets.

<details>
<summary>Connect an existing App</summary>

Open your existing App under GitHub Settings, verify the App ID and private key, then confirm Kooraseru/Template is installed.

Set these permissions in **Permissions & events**, then approve any installation
permission update:

Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

</details>

<details>
<summary>Register and connect a new App</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


</details>


</details></td><td align="center"><img alt="info" src="https://shieldcn.dev/badge/info.svg?variant=branded&amp;size=default&amp;color=5385B1&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code></td></tr>
<tr><td align="center"><a id="b-app-update"></a><details><summary><strong>Update App installation permissions</strong></summary>

<details open>
<summary>Update the configured App on GitHub</summary>

1. [Open the owner's Apps](https://github.com/settings/apps). Select the App whose ID matches `CI_APP_ID` in [Actions variables](https://github.com/Kooraseru/Template/settings/variables/actions) or [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
2. Open **Permissions & events**. Apply these requirements:

   Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

3. Click **Save changes**.
4. Open **Install App**. Select the repository owner's installation, include `Kooraseru/Template`, and approve any pending permission request.
5. For an authentication rejection, verify the stored App ID and private key belong to the same App. Replace `CI_APP_PRIVATE_KEY` in [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions) if its key was revoked.

<details>
<summary>Retry with GitHub CLI (Bash)</summary>

```bash
gh run rerun 41562908008 --failed --repo Kooraseru/Template
```

</details>

<details>
<summary>Retry on GitHub</summary>

[Open the run](https://github.com/Kooraseru/Template/actions). Click **Re-run jobs**, then **Re-run failed jobs**.

</details>

</details>


</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code></td></tr>
<tr><td align="center"><a id="b-app-restore"></a><details><summary><strong>Restore existing App credentials</strong></summary>

1. [Open the owner's Apps](https://github.com/settings/apps) and select the App to connect to this repository.
2. Open **General** and copy its numeric **App ID**.
3. Locate its saved private key. Generate a new key only if you no longer have one.
4. Open **Install App**, select the repository owner's installation, and confirm `Kooraseru/Template` is included.


</details></td><td align="center"><img alt="neutral" src="https://shieldcn.dev/badge/neutral.svg?variant=branded&amp;size=default&amp;color=64748B&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>bootstrap/auth</code></td></tr>
<tr><td align="center"><a id="b-execution-error"></a><details><summary><strong>Execution stopped</strong></summary>

CI stopped before it could complete this operation. Open the run logs for the reported error. Unfinished work is not reported as completed.

</details></td><td align="center"><img alt="failure" src="https://shieldcn.dev/badge/failure.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>application/build/server</code></td></tr>
<tr><td align="center"><a id="b-response-transfer"></a><details><summary><strong>Some response details are unavailable</strong></summary>

Some component response fragments could not be downloaded. The component job outcomes are still shown. Open the affected jobs' logs for missing details. Unavailable fragments are not treated as evidence that an operation succeeded.

</details></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td><code>releases/publish</code></td></tr>
</tbody></table>

</details>

---

## C. Components own their attachments

<details>
<summary><strong>Open full nested component-card report</strong></summary>

<h1 align="center">CI Execution</h1>
<p align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></p>
<p align="center">Each component owns its complete attachment body; nested groups stay expandable.</p>
<table width="100%"><thead><tr><th align="left"><details open><summary><strong>bootstrap</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>auth</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Credential and source checks complete

<details><summary>Update credential permissions</summary>

**Credential: CI_WORKFLOW_TOKEN**

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, workflow

**Missing scopes:** workflow

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_WORKFLOW_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_WORKFLOW_TOKEN`.
2. Under **Select scopes**, enable: repo, workflow.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
4. Click the pencil beside `CI_WORKFLOW_TOKEN`. If it is absent, click **New repository secret** and use this name:

   ```text
   CI_WORKFLOW_TOKEN
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>



</details>

<details><summary>Connect or register a GitHub App</summary>

Choose an App connection method, then save its credentials using one of the
methods below. Only credential names belong in configuration. Store the private
key in GitHub Actions secrets.

<details>
<summary>Connect an existing App</summary>

Open your existing App under GitHub Settings, verify the App ID and private key, then confirm Kooraseru/Template is installed.

Set these permissions in **Permissions & events**, then approve any installation
permission update:

Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

</details>

<details>
<summary>Register and connect a new App</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


</details>


</details>

<details><summary>Update App installation permissions</summary>

<details open>
<summary>Update the configured App on GitHub</summary>

1. [Open the owner's Apps](https://github.com/settings/apps). Select the App whose ID matches `CI_APP_ID` in [Actions variables](https://github.com/Kooraseru/Template/settings/variables/actions) or [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
2. Open **Permissions & events**. Apply these requirements:

   Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

3. Click **Save changes**.
4. Open **Install App**. Select the repository owner's installation, include `Kooraseru/Template`, and approve any pending permission request.
5. For an authentication rejection, verify the stored App ID and private key belong to the same App. Replace `CI_APP_PRIVATE_KEY` in [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions) if its key was revoked.

<details>
<summary>Retry with GitHub CLI (Bash)</summary>

```bash
gh run rerun 41562908008 --failed --repo Kooraseru/Template
```

</details>

<details>
<summary>Retry on GitHub</summary>

[Open the run](https://github.com/Kooraseru/Template/actions). Click **Re-run jobs**, then **Re-run failed jobs**.

</details>

</details>


</details>

<details><summary>Restore existing App credentials</summary>

1. [Open the owner's Apps](https://github.com/settings/apps) and select the App to connect to this repository.
2. Open **General** and copy its numeric **App ID**.
3. Locate its saved private key. Generate a new key only if you no longer have one.
4. Open **Install App**, select the repository owner's installation, and confirm `Kooraseru/Template` is included.


</details></td></tr>
</tbody></table>

</details></th></tr></thead></table>

<table width="100%"><thead><tr><th align="left"><details open><summary><strong>application</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>lint</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Luau and Bash style checks

No additional attachment</td></tr>
<tr><td colspan="3"><details open><summary><strong>build</strong> (nested group)</summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>client</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Build artifacts: 3

No additional attachment</td></tr>
<tr><td><strong>server</strong></td><td align="center"><img alt="failed" src="https://shieldcn.dev/badge/failed.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Native dependency compilation failed

<details><summary>Execution stopped</summary>

CI stopped before it could complete this operation. Open the run logs for the reported error. Unfinished work is not reported as completed.

</details></td></tr>
</tbody></table>

</details></td></tr>
</tbody></table>

</details></th></tr></thead></table>

<table width="100%"><thead><tr><th align="left"><details open><summary><strong>branches</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>protect</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Protected branch: source

<details><summary>Ruleset permissions and API diagnostic</summary>

**Sync result:** Failed: GitHub rejected the ruleset operation

| Credential | Required access |
| --- | --- |
| Configured GitHub App | Repository **Administration: Read and write**, approved on the installation |
| Secret `CI_RULESETS_TOKEN` | Fine-grained PAT **Administration: Read and write** for this repository, or a classic PAT with `repo` scope and administrative repository access |

<details>
<summary>Show permissions, API diagnostic, and next steps</summary>

**Observed result:** Rulesets API PUT failed (HTTP 422): /bypass_actors and /conditions/ref_name/exclude must be arrays.

1. Open the GitHub App's **Permissions & events** and grant repository **Administration: Read and write**, then approve the installation's permission update.
2. Alternatively, configure `CI_RULESETS_TOKEN` as a repository Actions secret with the required access.
3. If the API returned **HTTP 422**, authentication succeeded far enough to submit a ruleset change. Inspect the API validation message and the source TOML rule parameters; changing credentials alone will not resolve an invalid payload.

[GitHub ruleset API permissions and validation](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)

</details>


</details></td></tr>
</tbody></table>

</details></th></tr></thead></table>

<table width="100%"><thead><tr><th align="left"><details open><summary><strong>labels</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>sync</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>8 labels verified

No additional attachment</td></tr>
</tbody></table>

</details></th></tr></thead></table>

<table width="100%"><thead><tr><th align="left"><details open><summary><strong>packages</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>build</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Package archive generated

No additional attachment</td></tr>
<tr><td><strong>publish</strong></td><td align="center"><img alt="skipped" src="https://shieldcn.dev/badge/skipped.svg?variant=branded&amp;size=default&amp;color=64748B&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Separate Check Run: neutral

<details><summary>Enable neutral reporting</summary>

CI received the configured App ID and private key, but GitHub rejected the
operation. Update that App's installation or permissions using Option 1.
Credential presence alone does not establish that its permissions are sufficient.


**Observed result:** Neutral Check Run could not be created (HTTP 403).

<details open>
<summary>Option 1: Enable neutral reporting</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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

1. [Edit execution settings](https://github.com/Kooraseru/Template/blob/source/repo/config/ci/execution.toml).
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

Repository Checks: Read and write; installed on Kooraseru/Template

The component skipped. CI then tried to report `neutral`, but could not create
the Check Run. The reporting job therefore failed.

A classic PAT cannot create Check Runs. Adding PAT scopes will not fix this
operation. The PAT can continue serving other configured CI tasks.

[GitHub Check Run requirements](https://docs.github.com/en/rest/checks/runs#create-a-check-run).

</details>


</details></td></tr>
</tbody></table>

</details></th></tr></thead></table>

<table width="100%"><thead><tr><th align="left"><details open><summary><strong>pages</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>deploy</strong></td><td align="center"><img alt="pending" src="https://shieldcn.dev/badge/pending.svg?variant=branded&amp;size=default&amp;color=8B75B5&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Awaiting deployment environment

No additional attachment</td></tr>
</tbody></table>

</details></th></tr></thead></table>

<table width="100%"><thead><tr><th align="left"><details open><summary><strong>projects</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>sync</strong></td><td align="center"><img alt="blocked" src="https://shieldcn.dev/badge/blocked.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>CI_PROJECTS_TOKEN requires project scope

<details><summary>Projects: credential needed</summary>

## Projects: credential needed

Configure `CI_PROJECTS_TOKEN` to manage Projects owned by **Kooraseru**.
Choose a method below.

<details open>
<summary>Use a classic PAT - personal account or organization</summary>

<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_PROJECTS_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_PROJECTS_TOKEN`.
2. Under **Select scopes**, enable: repo, project, read:org.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
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

<details>
<summary>Use a GitHub App - organization-owned Projects only</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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
<summary>Required permissions and credential rules</summary>

**Classic PAT scopes** (combined for roles sharing this secret):

repo, project, read:org

**App organization permissions:**

Repository Checks: Read and write; installed on Kooraseru/Template

Personal-account Projects use the PAT path above. This template's installed-App
Projects path supports organization ownership. The built-in GITHUB_TOKEN cannot
manage account-owned Projects.

Token and key values belong in Actions secrets. Configuration stores their names.

</details>


</details>

<details><summary>Projects: update credential access</summary>

## Projects: update credential access

The supplied credential could not authorize Projects synchronization for
**Kooraseru**. Update `CI_PROJECTS_TOKEN` or the configured App below.

<details>
<summary>Show the permission check result</summary>

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, project

**Missing scopes:** project

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


Synchronization was skipped; earlier partial changes may remain.

</details>

<details open>
<summary>Use a classic PAT - personal account or organization</summary>

<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_PROJECTS_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_PROJECTS_TOKEN`.
2. Under **Select scopes**, enable: repo, project, read:org.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
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

<details>
<summary>Use a GitHub App - organization-owned Projects only</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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
<summary>Required permissions and credential rules</summary>

**Classic PAT scopes** (combined for roles sharing this secret):

repo, project, read:org

**App organization permissions:**

Repository Checks: Read and write; installed on Kooraseru/Template

Personal-account Projects use the PAT path above. This template's installed-App
Projects path supports organization ownership. The built-in GITHUB_TOKEN cannot
manage account-owned Projects.

Token and key values belong in Actions secrets. Configuration stores their names.

</details>


</details></td></tr>
</tbody></table>

</details></th></tr></thead></table>

<table width="100%"><thead><tr><th align="left"><details open><summary><strong>releases</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>publish</strong></td><td align="center"><img alt="failed" src="https://shieldcn.dev/badge/failed.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Release gate rejected publish

<details><summary>Update credential permissions</summary>

**Credential: CI_WORKFLOW_TOKEN**

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, workflow

**Missing scopes:** workflow

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_WORKFLOW_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_WORKFLOW_TOKEN`.
2. Under **Select scopes**, enable: repo, workflow.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
4. Click the pencil beside `CI_WORKFLOW_TOKEN`. If it is absent, click **New repository secret** and use this name:

   ```text
   CI_WORKFLOW_TOKEN
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>



</details>

<details><summary>Some response details are unavailable</summary>

Some component response fragments could not be downloaded. The component job outcomes are still shown. Open the affected jobs' logs for missing details. Unavailable fragments are not treated as evidence that an operation succeeded.

</details></td></tr>
</tbody></table>

</details></th></tr></thead></table>

<table width="100%"><thead><tr><th align="left"><details open><summary><strong>rulesets</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>sync</strong></td><td align="center"><img alt="failed" src="https://shieldcn.dev/badge/failed.svg?variant=branded&amp;size=default&amp;color=D95D66&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>HTTP 422: invalid API body

<details><summary>Ruleset permissions and API diagnostic</summary>

**Sync result:** Failed: GitHub rejected the ruleset operation

| Credential | Required access |
| --- | --- |
| Configured GitHub App | Repository **Administration: Read and write**, approved on the installation |
| Secret `CI_RULESETS_TOKEN` | Fine-grained PAT **Administration: Read and write** for this repository, or a classic PAT with `repo` scope and administrative repository access |

<details>
<summary>Show permissions, API diagnostic, and next steps</summary>

**Observed result:** Rulesets API PUT failed (HTTP 422): /bypass_actors and /conditions/ref_name/exclude must be arrays.

1. Open the GitHub App's **Permissions & events** and grant repository **Administration: Read and write**, then approve the installation's permission update.
2. Alternatively, configure `CI_RULESETS_TOKEN` as a repository Actions secret with the required access.
3. If the API returned **HTTP 422**, authentication succeeded far enough to submit a ruleset change. Inspect the API validation message and the source TOML rule parameters; changing credentials alone will not resolve an invalid payload.

[GitHub ruleset API permissions and validation](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)

</details>


</details></td></tr>
</tbody></table>

</details></th></tr></thead></table>

<table width="100%"><thead><tr><th align="left"><details open><summary><strong>attestations</strong></summary>

<table width="100%"><thead><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr></thead><tbody>
<tr><td><strong>publish</strong></td><td align="center"><img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"></td><td>Build provenance statement uploaded

<details><summary>Artifact provenance</summary>

## Artifact attestations

| Feature | Outcome |
| --- | --- |
| Build provenance | <img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"> |

The generated build artifact contains a verifiable provenance statement.



</details></td></tr>
</tbody></table>

</details></th></tr></thead></table>

</details>

---

## All 38 response templates

Each nested entry below is populated from its corresponding response Markdown source, including GitHub App creation, Check Run permissions, PAT verification and rejection states, personal and organization Projects access, ruleset API diagnostics, and partial execution reports. This section is intended for testing every template body independent of the three layout proposals.

<details>
<summary><strong>Report roots, overviews, and nesting</strong> (4 templates)</summary>

<details>
<summary><code>execution/overview/root.md</code></summary>

<table align="center">
<thead><tr><th align="center">Repository</th><th align="center">Source commit</th><th align="center">Selected components</th></tr></thead>
<tbody><tr><td align="center"><a href="https://github.com/Kooraseru/Template">Kooraseru/Template</a></td><td align="center"><code>bb828e2</code></td><td align="center">13</td></tr></tbody>
</table>

<p align="center"><a href="https://github.com/Kooraseru/Template/actions"><img alt="Open this run and its artifacts" src="https://shieldcn.dev/badge/Open_this_run_and_its_artifacts.svg?variant=branded&amp;size=default&amp;color=8B75B5&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=githubactions"></a>&nbsp;&nbsp;<a href="https://github.com/Kooraseru/Template"><img alt="Repository" src="https://shieldcn.dev/badge/Repository.svg?variant=branded&amp;size=default&amp;color=5385B1&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a></p>


</details>

<details>
<summary><code>execution/root.md</code></summary>

<div align="center">
<h1>CI Execution</h1>

<p align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF"></p>

<p>Rendered child content follows.</p>

<p>Nested child content: sample source values resolved.</p>

</div>


</details>

<details>
<summary><code>start/overview/root.md</code></summary>

<table align="center">
<thead><tr><th align="center">Repository</th><th align="center">Source commit</th><th align="center">Planned components</th></tr></thead>
<tbody><tr><td align="center"><a href="https://github.com/Kooraseru/Template">Kooraseru/Template</a></td><td align="center"><code>bb828e2</code></td><td align="center">13</td></tr></tbody>
</table>

<p align="center"><a href="https://github.com/Kooraseru/Template/actions"><img alt="Open this run" src="https://shieldcn.dev/badge/Open_this_run.svg?variant=branded&amp;size=default&amp;color=5385B1&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=github"></a>&nbsp;&nbsp;<a href="https://github.com/Kooraseru/Template/actions"><img alt="Open CI Execution" src="https://shieldcn.dev/badge/Open_CI_Execution.svg?variant=branded&amp;size=default&amp;color=8B75B5&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF&amp;logo=githubactions"></a></p>


</details>

<details>
<summary><code>start/root.md</code></summary>

<div align="center">
<h1>CI Start</h1>

<p align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF"></p>

<p>Rendered child content follows.</p>

<p>Nested child content: sample source values resolved.</p>

</div>


</details>

</details>

<details>
<summary><strong>Component and attachment containers</strong> (6 templates)</summary>

<details>
<summary><code>shared/attention.md</code></summary>

### Next steps

<p align="center"><a href="#gallery-template-authorization">Review required permissions</a></p>


</details>

<details>
<summary><code>shared/components/component/root.md</code></summary>

<tr><td align="center"><strong>packages</strong></td><td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF"></td><td align="center"><a href="#gallery-template-authorization">View record</a></td></tr>


</details>

<details>
<summary><code>shared/components/group/root.md</code></summary>

<table width="100%">
<thead>
<tr>
<th align="left">
<details open>
<summary><strong>packages</strong></summary>

<table><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr><tr><td>build</td><td>passed</td><td>Completed</td></tr></table>

<p>Nested child content: sample source values resolved.</p>

</details>
</th>
</tr>
</thead>
</table>


</details>

<details>
<summary><code>shared/components/root.md</code></summary>

## Components

<table><tr><th align="center">Component/Attachment</th><th align="center">Outcome</th><th align="center">Additional Notes</th></tr><tr><td>bootstrap/auth</td><td>passed</td><td>Credentials verified</td></tr></table>


</details>

<details>
<summary><code>shared/records/record/root.md</code></summary>

<tr>
<td align="center"><img alt="warning" src="https://shieldcn.dev/badge/warning.svg?variant=branded&amp;size=default&amp;color=C98B36&amp;labelTextColor=FFFFFF"></td>
<td>
<a id="response-88"></a>
<details>
<summary><strong>Artifact provenance</strong></summary>

## Artifact attestations

| Feature | Outcome |
| --- | --- |
| Build provenance | <img alt="passed" src="https://shieldcn.dev/badge/passed.svg?variant=branded&amp;size=default&amp;color=6DBE93&amp;labelTextColor=FFFFFF&amp;logoColor=FFFFFF"> |

The generated build artifact contains a verifiable provenance statement.



</details>
</td>
<td>attestations/publish</td>
</tr>


</details>

<details>
<summary><code>shared/records/root.md</code></summary>

## Details and next steps

<table>
<thead>
<tr><th align="center">Status</th><th>Attachment</th><th>Affected components</th></tr>
</thead>
<tbody>
<tr><td>Artifact provenance</td><td>success</td><td>attestations/publish</td></tr>
</tbody>
</table>

<p>Nested child content: sample source values resolved.</p>


</details>

</details>

<details>
<summary><strong>GitHub App and Check Run states</strong> (12 templates)</summary>

<details>
<summary><code>shared/authorization/app-account-organization.md</code></summary>

1. [Create the App on organization Kooraseru, with fields prefilled](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).


</details>

<details>
<summary><code>shared/authorization/app-account-personal.md</code></summary>

1. [Create the App on your personal account, with fields prefilled](https://github.com/settings/apps/new).


</details>

<details>
<summary><code>shared/authorization/app-account.md</code></summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).


</details>

<details>
<summary><code>shared/authorization/app-connect.md</code></summary>

Choose an App connection method, then save its credentials using one of the
methods below. Only credential names belong in configuration. Store the private
key in GitHub Actions secrets.

<details>
<summary>Connect an existing App</summary>

Open your existing Kooraseru-Template-CI GitHub App installation and confirm its repository access.

Set these permissions in **Permissions & events**, then approve any installation
permission update:

Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

</details>

<details>
<summary>Register and connect a new App</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


</details>


</details>

<details>
<summary><code>shared/authorization/app-registration.md</code></summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


</details>

<details>
<summary><code>shared/authorization/app-restore.md</code></summary>

1. [Open the owner's Apps](https://github.com/settings/apps) and select the App to connect to this repository.
2. Open **General** and copy its numeric **App ID**.
3. Locate its saved private key. Generate a new key only if you no longer have one.
4. Open **Install App**, select the repository owner's installation, and confirm `Kooraseru/Template` is included.


</details>

<details>
<summary><code>shared/authorization/app-setup.md</code></summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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
<summary><code>shared/authorization/app-state-configured.md</code></summary>

CI received the configured App ID and private key, but GitHub rejected the
operation. Update that App's installation or permissions using Option 1.
Credential presence alone does not establish that its permissions are sufficient.


</details>

<details>
<summary><code>shared/authorization/app-state-partial.md</code></summary>

CI received only part of the configured App credentials. Complete the pair
named `CI_APP_ID` and `CI_APP_PRIVATE_KEY` using Option 1.


</details>

<details>
<summary><code>shared/authorization/app-state-unavailable.md</code></summary>

CI did not receive the configured App credentials. This does not establish that
no App exists on your account. Option 1 connects an App to this repository;
Option 2 changes the skip policy without requiring an App.


</details>

<details>
<summary><code>shared/authorization/app-update.md</code></summary>

<details open>
<summary>Update the configured App on GitHub</summary>

1. [Open the owner's Apps](https://github.com/settings/apps). Select the App whose ID matches `CI_APP_ID` in [Actions variables](https://github.com/Kooraseru/Template/settings/variables/actions) or [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
2. Open **Permissions & events**. Apply these requirements:

   Repository: Administration (read/write), Checks (read/write), Contents (read/write), Workflows (read/write)

3. Click **Save changes**.
4. Open **Install App**. Select the repository owner's installation, include `Kooraseru/Template`, and approve any pending permission request.
5. For an authentication rejection, verify the stored App ID and private key belong to the same App. Replace `CI_APP_PRIVATE_KEY` in [Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions) if its key was revoked.

<details>
<summary>Retry with GitHub CLI (Bash)</summary>

```bash
gh run rerun 41562908008 --failed --repo Kooraseru/Template
```

</details>

<details>
<summary>Retry on GitHub</summary>

[Open the run](https://github.com/Kooraseru/Template/actions). Click **Re-run jobs**, then **Re-run failed jobs**.

</details>

</details>


</details>

<details>
<summary><code>shared/authorization/check-runs.md</code></summary>

CI received the configured App ID and private key, but GitHub rejected the
operation. Update that App's installation or permissions using Option 1.
Credential presence alone does not establish that its permissions are sufficient.


**Observed result:** The App lacks Checks: Read and write..

<details open>
<summary>Option 1: Enable neutral reporting</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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

1. [Edit execution settings](https://github.com/Kooraseru/Template/blob/source/repo/config/ci/execution.toml).
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

Repository Checks: Read and write; installed on Kooraseru/Template

The component skipped. CI then tried to report `neutral`, but could not create
the Check Run. The reporting job therefore failed.

A classic PAT cannot create Check Runs. Adding PAT scopes will not fix this
operation. The PAT can continue serving other configured CI tasks.

[GitHub Check Run requirements](https://docs.github.com/en/rest/checks/runs#create-a-check-run).

</details>


</details>

</details>

<details>
<summary><strong>PAT setup, evidence, and result states</strong> (8 templates)</summary>

<details>
<summary><code>shared/authorization/token-permissions.md</code></summary>

**Credential: CI_WORKFLOW_TOKEN**

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, workflow

**Missing scopes:** workflow

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_WORKFLOW_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_WORKFLOW_TOKEN`.
2. Under **Select scopes**, enable: repo, workflow.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
4. Click the pencil beside `CI_WORKFLOW_TOKEN`. If it is absent, click **New repository secret** and use this name:

   ```text
   CI_WORKFLOW_TOKEN
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>



</details>

<details>
<summary><code>shared/authorization/token-setup.md</code></summary>

<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_WORKFLOW_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_WORKFLOW_TOKEN`.
2. Under **Select scopes**, enable: repo, workflow.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
4. Click the pencil beside `CI_WORKFLOW_TOKEN`. If it is absent, click **New repository secret** and use this name:

   ```text
   CI_WORKFLOW_TOKEN
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>


</details>

<details>
<summary><code>shared/authorization/token/evidence.md</code></summary>

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, workflow

**Missing scopes:** workflow

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


</details>

<details>
<summary><code>shared/authorization/token/insufficient.md</code></summary>

GitHub's reported scope inventory is missing required classic PAT scopes.
Update this token's scopes or replace it, then update its named Actions secret.


</details>

<details>
<summary><code>shared/authorization/token/invalid.md</code></summary>

GitHub rejected the credential with HTTP 401. It may be expired, revoked, or
invalid. Renew or replace it, then update its named Actions secret.


</details>

<details>
<summary><code>shared/authorization/token/rejected.md</code></summary>

GitHub rejected the operation. Check the declared permissions, repository and
account access, App installation access, SSO authorization, and organization
policy. An operation rejection alone does not establish which permission is
missing.


</details>

<details>
<summary><code>shared/authorization/token/unverified.md</code></summary>

GitHub did not expose a verifiable classic scope inventory, or the inspection
request did not succeed. The required permissions are shown below, but this
check cannot establish which ones the credential has. The operation still
enforces access.


</details>

<details>
<summary><code>shared/authorization/token/verified.md</code></summary>

The declared classic PAT scopes are present. Repository access, account access,
SSO authorization, and organization policy still apply.


</details>

</details>

<details>
<summary><strong>Projects and rulesets</strong> (5 templates)</summary>

<details>
<summary><code>shared/projects-authorization/insufficient.md</code></summary>

## Projects: update credential access

The supplied credential could not authorize Projects synchronization for
**Kooraseru**. Update `CI_PROJECTS_TOKEN` or the configured App below.

<details>
<summary>Show the permission check result</summary>

Scope inspection completed. The token lacks one required classic PAT scope.

**Granted scopes:** repo

**Required scopes:** repo, workflow

**Missing scopes:** workflow

“Unknown” means GitHub did not expose a usable inventory; it does not mean the
credential has no permissions.


Synchronization was skipped; earlier partial changes may remain.

</details>


</details>

<details>
<summary><code>shared/projects-authorization/missing.md</code></summary>

## Projects: credential needed

Configure `CI_PROJECTS_TOKEN` to manage Projects owned by **Kooraseru**.
Choose a method below.


</details>

<details>
<summary><code>shared/projects-authorization/organization-setup.md</code></summary>

<details>
<summary>Use a GitHub App - organization-owned Projects only</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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


</details>

<details>
<summary><code>shared/projects-authorization/setup.md</code></summary>

<details open>
<summary>Use a classic PAT - personal account or organization</summary>

<details open>
<summary>GitHub CLI - copy/paste</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. Run this block. Paste the token when `gh secret set` asks:

   ```bash
   (
     gh auth status || gh auth login || exit 1
     gh secret set CI_WORKFLOW_TOKEN --repo Kooraseru/Template &&
     gh run rerun 41562908008 --failed --repo Kooraseru/Template
   )
   ```

4. [Open the run](https://github.com/Kooraseru/Template/actions).

</details>

<details>
<summary>Keep the existing token - edit its scopes</summary>

1. [Open classic tokens](https://github.com/settings/tokens) → select the token whose Note identifies `CI_WORKFLOW_TOKEN`.
2. Under **Select scopes**, enable: repo, workflow.
3. Click **Update token**. Keep the current repository secret if the token value did not change.
4. Retry the finished run:

   ```bash
   gh run rerun 41562908008 --failed --repo Kooraseru/Template
   ```

If the token was regenerated, expired, or revoked, use the CLI or website setup
to save a replacement value.

</details>

<details>
<summary>GitHub website - click by click</summary>

1. [Create the token with its name and scopes prefilled](https://github.com/settings/tokens/new).
2. Choose an expiration → **Generate token** → copy the token.
3. [Open repository Actions secrets](https://github.com/Kooraseru/Template/settings/secrets/actions).
4. Click the pencil beside `CI_WORKFLOW_TOKEN`. If it is absent, click **New repository secret** and use this name:

   ```text
   CI_WORKFLOW_TOKEN
   ```

5. Paste the token into **Secret** → **Update secret** or **Add secret**.
6. [Open the run](https://github.com/Kooraseru/Template/actions) → **Re-run jobs → Re-run failed jobs**.

</details>


</details>

<details>
<summary>Use a GitHub App - organization-owned Projects only</summary>

1. Open the prefilled registration form for your account type:
   - **Personal repository:** [create App on your personal account](https://github.com/settings/apps/new).
   - **Organization repository:** [create App on Kooraseru](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

2. Click **Create GitHub App**. If its name is taken, append a number. Name, description, homepage, permissions, and disabled webhooks are prefilled.
3. On **General**, copy the numeric **App ID**. Scroll to **Private keys** → **Generate a private key**. Keep the downloaded `.pem` file.
4. In the App sidebar, click **Install App** → **Install** beside the repository owner's account → **Only select repositories** → select `Kooraseru/Template` → **Install**.


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
       gh run rerun 41562908008 --failed --repo Kooraseru/Template
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
<summary>Required permissions and credential rules</summary>

**Classic PAT scopes** (combined for roles sharing this secret):

repo, project, read:org

**App organization permissions:**

Repository Checks: Read and write; installed on Kooraseru/Template

Personal-account Projects use the PAT path above. This template's installed-App
Projects path supports organization ownership. The built-in GITHUB_TOKEN cannot
manage account-owned Projects.

Token and key values belong in Actions secrets. Configuration stores their names.

</details>


</details>

<details>
<summary><code>shared/rulesets-authorization/permissions.md</code></summary>

**Sync result:** Failed: GitHub rejected the ruleset operation

| Credential | Required access |
| --- | --- |
| Configured GitHub App | Repository **Administration: Read and write**, approved on the installation |
| Secret `CI_RULESETS_TOKEN` | Fine-grained PAT **Administration: Read and write** for this repository, or a classic PAT with `repo` scope and administrative repository access |

<details>
<summary>Show permissions, API diagnostic, and next steps</summary>

**Observed result:** Rulesets API PUT failed (HTTP 422): /bypass_actors and /conditions/ref_name/exclude must be arrays.

1. Open the GitHub App's **Permissions & events** and grant repository **Administration: Read and write**, then approve the installation's permission update.
2. Alternatively, configure `CI_RULESETS_TOKEN` as a repository Actions secret with the required access.
3. If the API returned **HTTP 422**, authentication succeeded far enough to submit a ruleset change. Inspect the API validation message and the source TOML rule parameters; changing credentials alone will not resolve an invalid payload.

[GitHub ruleset API permissions and validation](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)

</details>


</details>

</details>

<details>
<summary><strong>Attestation and error reporting</strong> (3 templates)</summary>

<details>
<summary><code>shared/attestation-summary.md</code></summary>

## Artifact attestations

| Feature | Outcome |
| --- | --- |
| Build provenance | success |

Artifact SHA-256 verified



</details>

<details>
<summary><code>shared/error.md</code></summary>

CI stopped before it could complete this operation. Open the run logs for the
reported error. Unfinished work is not reported as completed.


</details>

<details>
<summary><code>shared/response-transfer.md</code></summary>

Some component response fragments could not be downloaded. The component job
outcomes are still shown. Open the affected jobs' logs for missing details.
Unavailable fragments are not treated as evidence that an operation succeeded.


</details>

</details>

---

## Feedback and next revision

| Choice | Options |
| --- | --- |
| Report root | A / B / C / hybrid |
| Group headers | Expandable table header / dedicated row / nested card |
| Attachments | Separate table / shared table / inside component |
| Default expansion | Failures only / all open / all closed |
| Additional Notes | Short inline context / linked detail / expandable diagnostic |
| Variants to keep | Call out specific rows or sections above |

This file is the design workspace. Once a format is chosen, the actual CI templates can be updated separately.

