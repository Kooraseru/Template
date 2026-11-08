# Luau rules and guidance

Use strict typing in hand-written Luau. Choose a module shape based on responsibility and keep side effects at explicit startup or lifecycle boundaries. Each executable rule links to its validator and fixture matrix.

- files: [file-system](files/file-system/README.md), [init-files](files/init-files/README.md), [module-roots](files/module-roots/README.md), [path-headers](files/path-headers/README.md)
- style: [blank-lines](style/blank-lines/README.md), [function-documentation](style/function-documentation/README.md), [naming](style/naming/README.md), [phase-comments](style/phase-comments/README.md), [indentation](style/indentation/README.md), [todo-comments](style/todo-comments/README.md)
- syntax: [control-flow](syntax/control-flow/README.md), [strings](syntax/strings/README.md), [types](syntax/types/README.md), [nested conditional expressions](syntax/nested-conditional-expressions/README.md)
- design: [declarative-data](design/declarative-data/README.md), [function-modules](design/function-modules/README.md), [functions](design/functions/README.md), [objects](design/objects/README.md)

## Manual review

- Review [entry-point responsibilities](files/entry-points.md) and [generated-file ownership](files/generated-files.md).
- Choose a [module structure](design/README.md) based on responsibility and lifetime.
- Review [expression clarity](syntax/expressions.md) and [type boundaries](syntax/types/guidance.md).
