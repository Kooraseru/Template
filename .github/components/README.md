# CI implementation

The native workflows under `.github/workflows/` are the entry points. This directory contains ordinary scripts invoked directly from YAML or the terminal. There is no component discovery, operation catalog, or generated workflow.

CI builds each declared host independently, transfers binaries with GitHub artifacts, tests them on the declared native runners, and stages release/package output. The documentation and generated branch builders run independently. The final `CI Required` job fails when any prerequisite fails.

Publication runs only after successful CI in the Publish workflow, with explicit target selection and job-scoped credentials. PR Results runs trusted default-branch code and reads untrusted PR artifacts as data. The packages repository contains standalone release verification, release publication, and generated branch publication actions; their commit pins are visible in the workflows.

Run the dependency loader before local checks. Run `node dependencies/packages/checks/testSuites/run.cjs` for the project regression suite. For individual commands, read the corresponding workflow steps. The local Actions task calls `act` directly; it is optional and does not replace native Windows runners.

At migration cutover, change the source branch's required status check to `CI Required` in GitHub settings, and verify the protected publication environments. Do not disable source protection to bypass the check.
