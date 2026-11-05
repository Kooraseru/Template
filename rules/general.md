# General coding conventions

- Read the relevant architecture and language guidance before changing an implementation.
- Preserve one authoritative editable owner for each configuration value, policy, or contract. Derive consumers from that owner.
- Discover extensible child components from their owning directory and validate their shared shape. Do not hardcode a separate inventory of instances; see [architecture](architecture.md).
- Prefer small, cohesive modules with explicit responsibilities over forwarding wrappers and decorative folders.
- Do not invent mandatory languages, platforms, or scaffolding for projects that do not require them.
- Use guards and validated boundaries to prevent avoidable failures. Reserve assertions for justified invariants in protected execution boundaries; do not scatter assertions in place of sound control flow.
- Validate changed behavior through relevant static checks, preflight, real execution, or focused tests where appropriate. Distinguish verified evidence from predictions and unavailable coverage.
- Never bypass validation, provenance, authorization, or release controls simply to make an operation succeed.
- Keep generated artifacts, credentials, and machine-local state out of version control.
