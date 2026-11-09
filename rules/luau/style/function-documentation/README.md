# Function documentation

Document module-level functions declared on a local module table returned by the file, even when the body is only a getter. Explain what the returned value means to a caller.
The same requirement applies when a function expression is assigned to a field of that returned table.

A named function with at least three top-level conditional branches (including `elseif` branches) or twenty top-level statements needs an attached purpose description. Describe ordering, side effects, or failures when those details matter. Tags alone and comments inside the body do not satisfy this requirement. Small, obvious helpers can stay undocumented.

Use triple-dash comments for LuaCATS annotations. This check reports a recognized tag written with two dashes, an empty supported tag, or an incomplete @param without a name and type. It reads actual Luau comment tokens.

A documentation block immediately above a named function warns on a simple `@param` name absent from the declaration. This applies to triple-dash comments and long comments. Detached comments and nested parameter fields require review. Native Luau types continue to describe the signature.

Attached function documentation rejects `@readonly`, which describes properties, and `@function` or `@method` tags that redeclare an existing function.

See [LuaCATS syntax](https://luals.github.io/wiki/annotations/), and the [fixture matrix](tests/TEST_MATRIX.md).

Attached multiline Moonwave comments are checked for a blank line between prose and the first parameter or return tag. Tag-only comments and fenced examples are allowed.

## Moonwave guidance

Use Moonwave-style documentation comments so `luau-lsp` can surface the contract in hover and signature assistance. Place the comment immediately before its function or method, with no unrelated statement between them.

Use `--[[ ... ]]` or `--[=[ ... ]=]` for multiline documentation. The validator accepts parameter descriptions with or without the optional `--` separator. The prose inside can run naturally. Short single-sentence comments can use `---`.

## Layout

1. Start with one sentence explaining the function's purpose or observable effect.
2. Describe relevant ordering, side effects, failure conditions, or ownership when they are not obvious.
3. Leave a blank line before tags.
4. Write `@param name Type -- description` for parameters requiring meaningful documentation.
5. Write `@return Type -- description` when the return needs explanation; repeat for each returned value if tagging returns explicitly.
6. Add metadata flags only when true and useful. Do not invent tags to decorate every function.

```luau
--[=[
Records an invocation attempt for a message binding, distinguishing dropped messages from successful dispatches.

@param network Network -- Network whose metrics are updated.
@param message Message -- Pipeline message being recorded.
]=]
function Metrics:Handle(network: Network, message: Message): ()
	const bucket = if message.dropped then self.drops else self.counts
	bucket[message.name] = (bucket[message.name] or 0) + 1
end

--[=[
Returns a snapshot of the metrics collected by this instance.

@return MetricsSnapshot -- Current counters grouped by dispatch outcome.
]=]
function Metrics:Snapshot(): MetricsSnapshot
	return { counts = table.clone(self.counts), drops = table.clone(self.drops) }
end
```

Do not duplicate a parameter's obvious type information solely to fill out a template. Luau's type annotations remain the source of truth; documentation describes semantics and usage. For a trivial private helper, one purpose comment or no comment may be more useful than a formal doc block.

## Supported metadata

Use tags supported by the tooling when they apply: `@deprecated version` and `@since version` for lifecycle information, `@yields` for yielding behavior, `@private` for genuine visibility boundaries, and `@error Type -- description` for meaningful failure contracts. Realm tags (`@server`, `@client`, `@plugin`) only make sense when the target runtime actually has those realms.

`@readonly` is restricted to property documentation, not function comments. Use `@within` when the documentation generator needs an explicit owning class. Do not misuse `@function` or `@method` to document a function already declared in source.

Moonwave-style tags are documentation metadata, not a substitute for Luau types or runtime validation. Avoid `any` in the implementation just because the comment names a concrete type.

References: [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) and [Moonwave tags](https://eryn.io/moonwave/docs/TagList/).
