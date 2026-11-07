# Language conventions

These files are reusable language and module-writing conventions. Start with [the language system](language-system.md) and [comments](comments.md), then read only the rules relevant to the source language and module responsibility.

- `bash/`: shell entry points, naming, argument arrays, control flow, and MSYS2 path boundaries.
- `luau/`: module roots, typing, file layout, and structure patterns.
- `low-level-languages/rust/`: modules, ownership, guard-first flow, documentation, and structure patterns.
- `web-languages/`: JavaScript, HTML, and CSS conventions for browser and presentation code.

No language becomes mandatory merely because guidance for it exists. Build systems and runtime ownership remain project-specific.
