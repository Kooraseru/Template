# Repository rules

This directory is the version-controlled source of coding-agent guidance. Files are ordinary Markdown. No KERO mount, runtime, or synchronization service is required to interpret them.

Read `general.md` and `architecture.md` first, followed by task-specific language rules and contracts. The generated, Git-ignored root `AGENTS.md` is a lightweight index; documentation here remains authoritative.

Use `bash ci/run.sh rules sync` to regenerate the local agent index. Use `bash ci/run.sh rules check` to validate that required rule documents and ignore policy exist. The checker does not modify files.

Migration is incremental: legacy `.kero/` documentation remains in the original tree until equivalent content has been reviewed and moved here.
