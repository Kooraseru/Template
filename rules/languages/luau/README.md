# Luau conventions

Use strict typing where the target runtime supports it and preserve the established file-shape conventions. Keep side effects at explicit executable or lifecycle boundaries. Avoid wrappers that only forward `require` calls.

Indent with [one literal tab per nesting level](language/indentation.md). Do not insert extra tabs or spaces to align code visually.

Treat Luau as the executable layer. Keep ordinary declarative catalogs and configuration in data formats, while preserving Luau tables for behavior, runtime state, and values that require computation.

Choose a single `name.luau` module when one script is sufficient. When meaningful child modules warrant a directory, `name/init.luau` is the normal coordinating module head; it must not exist solely to echo child exports.

See [directory roots](files/module-roots.md), [file layout](files/file-system.md), [control flow](language/control-flow.md), [indentation](language/indentation.md), [function documentation](language/function-documentation.md), [declarative data](declarative-data/README.md), and [strings](language/strings.md).

Template pilots the [path-header validator](files/path-headers/README.md).
