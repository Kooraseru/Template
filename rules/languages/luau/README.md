# Luau conventions

Follow the established Luau language rules when migrated from the previous guidance; new rules here are regular Markdown, not KERO instructions.

Use strict typing for repository Luau modules. Keep effects at the declared executable boundary. Prefer imports and exports that reflect actual module ownership; do not add a file solely to forward `require` calls.

See `files/module-roots.md` for `index.luau` versus `init.luau`.
