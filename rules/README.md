# Version-controlled repository rules

This directory is the source of coding-agent guidance: ordinary Markdown standards, workflows, contracts, and applicable language conventions. It has no KERO dependency.

Read `general.md` and `architecture.md` first. Then read the task-specific conventions under `languages/`, `workflows/`, and `contracts/`. Only use rules relevant to the files being changed.

`bash ci/run.sh rules sync` produces the local `AGENTS.md` index. `bash ci/run.sh rules check` validates tracked rule inputs and the ignored output. The generated entry point is disposable and not committed.
