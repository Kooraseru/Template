# General coding conventions

- Read the relevant architecture and language guidance before modifying implementation.
- Preserve one canonical owner for each configuration value, policy, and contract.
- Prefer small, cohesive modules with explicit responsibility over forwarding wrappers.
- Do not invent mandatory source languages or scaffolding for a language-agnostic template.
- Validate changed behavior with focused tests; distinguish tested facts from unverified assumptions.
- Never bypass validation, receipt, or authorization checks to make CI pass.
- Do not commit generated artifacts, secrets, or the local `AGENTS.md` index.
