-- .vscode/luau/lute/typedefs/std/syntax/init.luau
--!strict

-- Luau LSP declarations for the subset of Lute's syntax module used by lint rules.
export type SourceLocation = {
	beginLine: number,
	beginColumn: number,
	endLine: number,
	endColumn: number,
}

export type AstNode = {
	tag: string,
	node: AstNode?,
	value: unknown?,
	entries: { { kind: string, value: AstNode } }?,
	variables: { { name: { text: string } } }?,
	values: { AstNode }?,
	location: SourceLocation?,
}

export type AstStatLocal = AstNode & {
	variables: { { name: { text: string } } },
	values: { AstNode },
	location: SourceLocation,
}

export type AstStatBlock = AstNode

local syntax = {}

syntax.span = {
	create = function(_options: SourceLocation): SourceLocation?
		return nil
	end,
}

return syntax
