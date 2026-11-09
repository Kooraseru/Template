# Literal text and interpolation

Use a single quoted literal for constant text. The validator flags same-line concatenation of two ordinary quoted literals or a quoted literal and an interpolated string. It also flags quoted text placed directly inside interpolation braces. Multiline text, unknown operand types, and possible metamethod calls require review.

See [fixture matrix](tests/TEST_MATRIX.md).

The global `string.format` call warns when its only format specifier is plain `%s` and its value is an ordinary quoted literal. Escaped content, padding, dynamic values, and custom formatters stay outside this check.

A direct built-in tostring around a local or primitive literal is redundant when the string has exactly one interpolation. Custom conversions, function results, and strings with multiple interpolations stay for review because replacing a conversion can change evaluation order or argument handling.

## String guidance

Prefer backtick interpolation when a string combines literal text with values. Keep ordinary quoted literals for constant text. Use `table.concat` to assemble collections, and retain `string.format` when numeric precision, padding, or a specific representation matters.

```luau
local greeting = `Welcome, {name}.`
local summary = `Total: {price * count}`
local normalized = `Name: {string.upper(name)}`
```

Each brace pair contains an expression, including arithmetic or a function call. It does not contain a sequence of statements. Values are converted to text, so an extra `tostring` is normally unnecessary. Compute complicated expressions and operations with side effects in named locals before constructing the string.

Interpolation can invoke `__tostring`; replacing concatenation can change behavior for tables or userdata with custom metamethods. Preserve deliberate `__concat` behavior and do not use interpolation as validation, encoding, or escaping.

Inside a backtick literal, escape an opening brace with `\{`, a backtick with a backslash, and a backslash with `\\`. Doubling opening braces is invalid Luau. Use parentheses when passing an interpolated string to a function. Backtick literals cannot be used as string singleton types; retain quoted type literals.

Apply this preference when editing messages, paths, labels, and similar string construction. Avoid mechanical changes to patterns, serialized payloads, or code whose formatting is part of a contract.

Sources: [Luau syntax](https://luau.org/syntax/#string-interpolation) and the [implemented interpolation RFC](https://rfcs.luau.org/syntax-string-interpolation.html).

