# Language conventions

These version-controlled Markdown files are the authoritative, directly readable language guidance for this template. They do not depend on a global mount, a runtime rule server, or synchronization credentials.

Start with `language-system.md` and `comments.md`, then select the files for the actual language and module style being changed:

- `luau/`: Luau modules, directory roots, types, files, and structure patterns
- `rust/`: optional application Rust code writing, guard-first flow, ownership, modules, and responsibility-based structures
- `javascript/`, `html/`, `css/`: browser-facing conventions when applicable

Language guidance does not make that language mandatory or trigger a compiler smoke test. A consuming project may have any application language, but repository CI infrastructure is owned by Luau.
