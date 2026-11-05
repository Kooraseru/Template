# Luau conventions

Use strict typing where the target runtime supports it and preserve the established file-shape conventions. Keep side effects at explicit executable or lifecycle boundaries. Avoid wrappers that only forward `require` calls.

Choose a single `name.luau` module when one script is sufficient. When meaningful child modules warrant a directory, `name/init.luau` is the normal coordinating module head; it must not exist solely to echo child exports.

See [directory roots](files/module-roots.md), [file layout](files/file-system.md), [control flow](language/control-flow.md), and [strings](language/strings.md).
