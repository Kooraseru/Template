# Agent orchestration

These rules govern how a coordinating agent delegates, coordinates, isolates,
integrates, and verifies work performed by subagents. They apply regardless of
the agent tool or repository language.

Read the task contract before delegating. Before parallel edits, establish file
ownership and workspace boundaries. The coordinating agent remains responsible
for reviewing and integrating every result and verifying the combined change.

## Rules

- [Task contract](delegation/task-contract/README.md)
- [Task sizing](delegation/task-sizing/README.md)
- [Ownership and overlap](coordination/ownership-and-overlap/README.md)
- [Communication and blockers](coordination/communication-and-blockers/README.md)
- [Shared-workspace safety](isolation/shared-workspace-safety/README.md)
- [Worktree boundaries](isolation/worktree-boundaries/README.md)
- [Parent-owned integration](integration/parent-owns-integration/README.md)
- [Validation and handoff](integration/validation-and-handoff/README.md)

## Enforcement boundary

Automated checks can validate repository artifacts and declared outcomes. They
cannot establish that a delegated change was understood or integrated correctly
without inspecting the resulting diff and behavior. The coordinator must do
that review; a subagent's completion message is evidence to inspect, not an
integration result.
