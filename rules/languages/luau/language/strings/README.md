# Literal text and interpolation

Use a single quoted literal for constant text. The validator flags same-line concatenation of two ordinary quoted literals or a quoted literal and an interpolated string. It also flags quoted text placed directly inside interpolation braces. Multiline text, unknown operand types, and possible metamethod calls require review.

See [the language rule](../strings.md) and [fixture matrix](tests/TEST_MATRIX.md).

The global `string.format` call warns when its only format specifier is plain `%s` and its value is an ordinary quoted literal. Escaped content, padding, dynamic values, and custom formatters stay outside this check.
