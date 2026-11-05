--!strict

-- Luau LSP declarations for the subset of Lute's syntax module used by lint rules.
export type AstStatBlock = any

type SpanOptions = {
	beginLine: number,
	beginColumn: number,
	endLine: number,
	endColumn: number,
}

local syntax = {}

syntax.span = {
	create = function(_options: SpanOptions): any
		return nil
	end,
}

return syntax
