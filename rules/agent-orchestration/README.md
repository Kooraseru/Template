# Agent orchestration

These rules govern how a coordinating agent delegates, coordinates, isolates, integrates, and verifies work performed by subagents. They apply regardless of the agent tool or repository language.

Read the task contract before delegating. Before parallel edits, establish interfaces, dependencies, file ownership, and workspace boundaries. The coordinating agent remains responsible for reviewing and integrating every result and verifying the combined change.

Delegate only bounded work with an observable result. Parallel exploration and review are generally safer than competing edits to a shared working tree. Use independent worktrees for changes that cannot safely share file ownership, and serialize modifications of shared interfaces.

## Rules

- [Task contract](delegation/task-contract.md)
- [Task sizing](delegation/task-sizing.md)
- [Ownership and overlap](coordination/ownership-and-overlap.md)
- [Communication and blockers](coordination/communication-and-blockers.md)
- [Shared-workspace safety](isolation/shared-workspace-safety.md)
- [Worktree boundaries](isolation/worktree-boundaries.md)
- [Parent-owned integration](integration/parent-owns-integration.md)
- [Validation and handoff](integration/validation-and-handoff.md)

## Enforcement boundary

Automated checks can validate repository artifacts and declared outcomes. They cannot establish that a delegated change was understood or integrated correctly without inspecting the resulting diff and behavior. The coordinator must do that review; a subagent's completion message is evidence to inspect, not an integration result.

An agent's ability to create additional agents is not a reason to delegate every small task. Coordination overhead, overlapping edits, and shared mutable state can eliminate the gains from parallel work.
