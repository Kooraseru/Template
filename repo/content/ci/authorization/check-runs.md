## Neutral reporting unavailable

**The classic PAT method does not support creating Check Runs.** Adding PAT
scopes will not enable this operation.

Component: **{{component}}** · Result: **{{status}}**

<details open>
<summary>Enable neutral reporting — install a GitHub App</summary>

Works with personal repositories and organization repositories.

{{app_setup}}

</details>

<details>
<summary>Keep the classic PAT — choose a different skip result</summary>

1. [Open execution settings]({{execution_config_url}}) → click the pencil.
2. Under `[skip]`, replace the `default` line with:

   ```toml
   default = "success"
   ```

   Use `failure` instead if skipped work should fail CI.
3. Commit the change to the default branch. The new run uses the new policy;
   rerunning an old commit keeps its old policy.

</details>

<details>
<summary>Technical details and required permissions</summary>

**Required Check Run repository permissions:**

{{app_permissions}}

The App setup link also includes bootstrap permissions when bootstrap is enabled.
No neutral Check Run was created; the component remains skipped and its reporting
job fails. The existing PAT is not missing merely because this App backend is
unavailable.

[GitHub Check Run requirements](https://docs.github.com/en/rest/checks/runs#create-a-check-run).

</details>
