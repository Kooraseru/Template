# Shared-workspace safety

Assume agents share the active checkout unless the environment explicitly
provides isolation. Inspect repository status before editing and preserve
pre-existing user changes, including untracked files and edits made by other
agents.

Do not use reset, clean, recursive deletion, or broad replacement to resolve
uncertainty. Limit changes to the assigned scope and inspect the final diff for
unintended edits before handing work back.
