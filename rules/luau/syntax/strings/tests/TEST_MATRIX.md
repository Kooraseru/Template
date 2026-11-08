# Constant string concatenation fixtures

- [Invalid](invalid/example.luau) produces one finding across the construct.
- [Valid](valid/example.luau) passes.
- [Review](review/example.luau) produces no finding. The operand contract and potential metamethod behavior need context before rewriting.
- [Split interpolation](invalid/split-interpolation.luau) reports concatenation with a quoted prefix or suffix and a quoted literal inside interpolation braces.
- [Interpolation expressions](valid/interpolation-expressions.luau) accepts variable and arithmetic interpolation.
- [Constant format](invalid/constant-format.luau) warns on formatting an already quoted string with plain `%s`.
- [Formatted representation](valid/formatted-representation.luau) accepts meaningful padding.
- [Shadowed format](review/shadowed-format.luau) leaves a project-owned formatter for review.
- [Binary format](review/binary-format.luau) leaves strings containing an embedded NUL for review.

- [Redundant tostring](invalid/redundant-tostring.luau) reports built-in conversion around a local or literal in a single interpolation.
- [Conversion order](review/tostring-conversion-order.luau) preserves explicit conversion among other interpolations and around a call.
- [Replaced tostring](review/replaced-tostring.luau) leaves a local binding reassigned to a project formatter alone.
- [Custom tostring](valid/custom-tostring.luau) preserves a local formatter.
