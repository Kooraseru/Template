# Luau conventions

Use strict typing where the target runtime supports it and preserve the established file-shape conventions. Keep side effects at explicit executable or lifecycle boundaries. Avoid wrappers that only forward `require` calls.

Indent with [one literal tab per nesting level](language/indentation.md). Do not insert extra tabs or spaces to align code visually.

Treat Luau as the executable layer. Keep ordinary declarative catalogs and configuration in data formats, while preserving Luau tables for behavior, runtime state, and values that require computation.

Choose a single `name.luau` module when one script is sufficient. When meaningful child modules warrant a directory, `name/init.luau` is the normal coordinating module head; it must not exist solely to echo child exports.

See [directory roots](files/module-roots.md), [file layout](files/file-system.md), [control flow](language/control-flow.md), [indentation](language/indentation.md), [function documentation](language/function-documentation.md), [declarative data](declarative-data/README.md), and [strings](language/strings.md).

## Executable checks

Template runs these validators in the **Rules** check. Each validator page links to its fixture matrix and describes the syntax it covers.

| Area | Checks |
| --- | --- |
| Files | [Path headers](files/path-headers/README.md), [strict directives and section headers](files/file-system/README.md), [placeholder directory heads](files/init-files/README.md) |
| Language | [Blank-line separation](language/blank-lines/README.md), [control flow](language/control-flow/README.md), [function declarations](language/functions/README.md), [function documentation](language/function-documentation/README.md), [naming](language/naming/README.md), [strings](language/strings/README.md), [types](language/types/README.md) |
| Structure | [Declarative data](declarative-data/README.md), [single-operation modules](structures/functional/function-modules/README.md), [object construction, receivers, and inheritance](structures/oop/objects/README.md) |

Indentation uses [literal tabs](language/indentation.md); blank-line separation is checked by the Luau rule above. Numeric separators are optional and covered by the [naming fixtures](language/naming/tests/TEST_MATRIX.md).

## Review

Use the validator matrices for examples that need additional context. [Entry-point responsibilities](files/entry-points.md), [generated-file ownership](files/generated-files.md), [resolver conventions](files/module-roots.md), [expression clarity](language/expressions.md), [composition](structures/functional/composition.md), [shared interfaces](structures/oop/interfaces.md), and [stateful module lifetimes](structures/procedural/stateful-modules.md) still require architectural review. [ECS](structures/ecs/ecs-system.md) defines responsibility boundaries and leaves concrete conventions to an adopting repository.
