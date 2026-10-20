# Local testing

## Execution

Use GitHub Local Actions in VS Code to run `.github/workflows/ci.yml` through act.
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

A skipped or unavailable target is untested, not passed. Check prerequisites inside
the actual runner or container; host availability alone is insufficient.

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
