# Luau strings and interpolation

Prefer backtick interpolation when a string combines literal text with values.
Keep ordinary quoted literals for constant text. Use `table.concat` to assemble
collections, and retain `string.format` when numeric precision, padding, or a
specific representation matters.

```luau
local greeting = `Welcome, {name}.`
local summary = `Total: {price * count}`
local normalized = `Name: {string.upper(name)}`
```

Each brace pair contains an expression, including arithmetic or a function call.
It does not contain a sequence of statements. Values are converted to text, so an
extra `tostring` is normally unnecessary. Compute complicated expressions and
operations with side effects in named locals before constructing the string.

Interpolation can invoke `__tostring`; replacing concatenation can change behavior
for tables or userdata with custom metamethods. Preserve deliberate `__concat`
behavior and do not use interpolation as validation, encoding, or escaping.

Inside a backtick literal, escape an opening brace with `\{`, a backtick with a
backslash, and a backslash with `\\`. Doubling opening braces is invalid Luau.
Use parentheses when passing an interpolated string to a function. Backtick
literals cannot be used as string singleton types; retain quoted type literals.

Apply this preference when editing messages, paths, labels, and similar string
construction. Avoid mechanical changes to patterns, serialized payloads, or code
whose formatting is part of a contract.

Sources: [Luau syntax](https://luau.org/syntax/#string-interpolation) and the
[implemented interpolation RFC](https://rfcs.luau.org/syntax-string-interpolation.html).
