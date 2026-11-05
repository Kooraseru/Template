# Worktree boundaries

Use an isolated worktree only when the task or environment explicitly requests
one or provides one. Do not assume a subagent has an isolated branch or checkout.

When a worktree is used, record its base and scope, and return the resulting
commit or focused patch plus verification. The coordinating agent must inspect
and integrate that result into the requested checkout; isolation does not
replace integration.
