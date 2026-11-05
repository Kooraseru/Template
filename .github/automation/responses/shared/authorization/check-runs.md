{{app_detection}}

**Observed result:** {{status}}.

<details open>
<summary>Option 1: Enable neutral reporting</summary>

{{app_setup}}

</details>

<details>
<summary>Option 2: Change how CI handles skipped work</summary>

1. [Edit execution settings]({{execution_config_url}}).
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

{{app_permissions}}

The component skipped. CI then tried to report `neutral`, but could not create
the Check Run. The reporting job therefore failed.

A classic PAT cannot create Check Runs. Adding PAT scopes will not fix this
operation. The PAT can continue serving other configured CI tasks.

[GitHub Check Run requirements](https://docs.github.com/en/rest/checks/runs#create-a-check-run).

</details>
