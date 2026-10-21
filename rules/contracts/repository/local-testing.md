# Local testing

## Execution

Use GitHub Local Actions in VS Code to run `.github/workflows/ci.yml` through act.
Follow [editor automation](../../standards/editor-automation.md) for non-GUI access.

Trigger the extension itself so the run appears in its History with job results
and logs the user can inspect. Calling act directly is not an equivalent workflow
validation entry point, even when it executes the same YAML. Never manufacture or
inject extension history records. If extension invocation is unavailable, disclose
that limitation instead of silently substituting a direct act run.
Inspect its existing History and saved logs before starting another run. Leave a
user-started run running unless asked to stop it; do not launch an overlapping CLI
run just to obtain logs.

Local testing, like repository PR submission, skips publication stages and focuses
on validating, building, testing, and packaging artifacts. Repository trees,
documentation, and release previews may be generated as artifacts, but are not
pushed, deployed, or publicly released. Hosted authorized source execution is the
context that can proceed to publication.

Local iteration must support testing current worktree changes. Trusted receipt
acceptance is a separate operation, not a prerequisite for ordinary local artifact
testing. Do not treat local output as accepted publication evidence merely because
its build succeeded.

## Platform coverage

Select the images and targets that the current machine can actually exercise.
A local run does not need to build every image. Known compatible images can be
validated individually, with the selected coverage reported explicitly.

Windows on ARM can exercise compatible Docker environments and available native
tools. It cannot establish native macOS behavior without a Mac. Emulation and
cross-compilation are useful checks but are not native execution evidence. Use
appropriate hosted or physical runners for platforms unavailable locally.

Once an environment is runnable, failed validation, probes, compilation, packaging,
or artifact transfer is an error. Do not relabel those failures as device-related
skips. Record unavailable coverage separately from execution outcomes.

A skipped or unavailable target is untested, not passed. Check prerequisites inside
the actual runner or container; host availability alone is insufficient.

## Command-only extension access

With this repository open in a trusted VS Code workspace and GitHub Local Actions
installed, install the local adapter once. Python 3, the `code` CLI, Lune, and
Bash must be available to the calling agent:


```sh
python .github/integration/editor-bridge/install.py
```

The installer uses the existing VS Code CLI and extension host. It requires no npm
or separately installed Node runtime. Adapter updates can require a later editor restart; do not restart an active
workflow or extension host merely to apply an adapter update. If the editor does not activate it immediately,
report the missing bridge rather than initiating a different runner.

From the workspace root, any agent can query or start the real extension task:

```sh
bash .github/integration/run.sh .github/integration/local-actions.luau status
bash .github/integration/run.sh .github/integration/local-actions.luau start ci.yml
```

On Windows, use Git Bash for the command wrapper. `status` reports extension task
names, running state, genuine log paths, and the installed extension's log directory.
Task observations cover the bridge session; older saved logs remain in that directory. A start response can precede the task
start event; query status afterward. A start request is refused while a task is
active. When execution ends, inspect its saved log for the exit code and job results;
a finished task alone does not mean success. The extension remains the owner of
History and logs.

Discovery uses `.kero/.runtime/local-actions/session.json` in the open workspace.
The client handles the session credential internally. Do not commit or print that
file, create it by hand, or copy it between machines. A missing or unresponsive
session means editor access is unavailable. After a timeout, query status and logs
before retrying; an already accepted command may still complete. The adapter supports file workspaces with multiple workflows. `start` selects
`ci.yml` by default; pass another workflow filename explicitly to run it alone.
The Luau client parses the selected YAML and supplies the workflow object to the
installed extension's `githubLocalActions.runWorkflow` command. The bridge verifies
that the source still matches the workspace file before calling that command.
It does not spawn act itself.

The local act executable still needs the artifact-protocol support documented in
`fabricator/distribution/images/act/README.md`. `.actrc` reuses installed runner
images rather than forcing every run to pull; an absent required image still needs
a working registry connection. Never classify a failed pull as a successful build.

## Logs and results

The extension stores logs beneath the active VS Code profile's user globalStorage
folder in `sanjulaganepola.github-local-actions`. Discover this location rather than
committing an absolute installation path. Filenames include run name and timestamp.

Confirm repository and run identity, inspect the first failing step with context,
and distinguish root failures from downstream skips. Report selected targets,
runner architecture, worktree/revision, and what actually ran. Module checks can
supplement workflow evidence but do not prove that the workflow passes.

Saved-log access does not imply live extension UI control. Keep raw logs out of
contract data and avoid exposing credentials when reporting excerpts.
