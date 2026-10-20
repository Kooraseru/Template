# Editor-host adapter

This optional VS Code extension supplies the command-only access described in
[local testing](../../../.kero/data/contracts/repository/local-testing.md).
It runs only in VS Code's existing extension host. Its package manifest is required
by VS Code; no npm dependencies, standalone Node installation, or JavaScript CI
controller are introduced.

The Python installer packages a VSIX using the standard library and installs it
through `code`. Installation activates a trusted open file workspace when supported
by the editor. The mailbox is session-authenticated, workspace-scoped, and ignored
by Git. The Luau client atomically submits requests and removes timed-out requests.
Only `status` and `start` are exposed. The adapter calls GitHub Local Actions' own
registered command and observes public VS Code task events for genuine log paths.
It never edits the extension's History, private database, or implementation.

This is a host integration, not a sandbox. Workspace trust and the installed
extension's execution permissions still apply. File workspace access must be shared
with the calling agent. Remote/container editor environments require the adapter
in the extension host that owns that workspace.

`start` selects a single workflow through `githubLocalActions.runWorkflow`, with
`ci.yml` as the client's default. Pass `template.yml` explicitly to assess the
independent maintenance workflow. The client supplies parsed YAML and the exact
source; the bridge verifies that source against the workspace file before invoking
the installed extension. It does not use the run-all-workflows command.

After installing an adapter update, an already loaded extension host may retain
the previous implementation until the next normal editor restart. Do not restart
an active workflow or the editor merely to force activation.

Adapter regression tests can run under the existing VS Code executable, without
installing Node or npm. Set `ELECTRON_RUN_AS_NODE=1` for that process and pass
`tests.cjs`. It mocks VS Code, verifies single-workflow selection, rejects stale
source and escaping filenames, and prevents overlapping starts. It creates no
extension History and is not a workflow execution test.
