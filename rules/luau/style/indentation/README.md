# Luau indentation

Leading indentation on code lines uses literal tabs. The validator highlights a prefix containing spaces, including mixed tabs and spaces. It uses token starts so multiline string contents and comment-only lines are outside this check. Exact indentation depth remains a review concern.

See the [fixture matrix](tests/TEST_MATRIX.md).

## Guidance

Indent with one literal tab (`\t`) for each syntactic nesting level. A function body has one tab, code inside its nested `if` or `for` has two, and so on. Never add a second tab to the same level for visual padding.

Use tabs for nesting, not runs of spaces or manual alignment. Do not mix spaces and tabs in leading indentation. If alignment is needed, prefer a clearer multiline expression over columns padded with whitespace.

```luau
const Registry = {}

function Registry.Add(name: string): ()
	if name ~= "" then
		Registry[name] = true
	end
end
```

Editors may render a tab as two, four, or eight columns; this rule governs the actual `\t` character in source, not its displayed width. Preserve deliberate semantic line breaks and do not introduce arbitrary line-width wrapping. For visual separation between larger blocks, see the [blank-line rule](../blank-lines/README.md).
