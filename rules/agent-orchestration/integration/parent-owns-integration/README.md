# Parent-owned integration

The coordinating agent owns the final result. It reviews each delegated diff,
checks that it meets the task contract, resolves overlaps, and integrates only
the needed changes. A subagent's report, branch, or commit is not complete work
until the coordinator has inspected it in context.

If a result is unsuitable, ask for a correction or make a scoped integration
change. Do not discard unrelated user or agent changes while resolving it.
