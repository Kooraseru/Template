-- dependencies/packages/ruleLinter/diagnostic.luau
--!strict

export type Severity = "error" | "warning" | "information" | "hint"

-- Lines and columns are one-based, with an exclusive end position.
export type Span = { line: number, column: number, endLine: number, endColumn: number }

export type Finding = {
	related: { Span }?,
	line: number,
	column: number,
	endLine: number,
	endColumn: number,
	severity: Severity,
	message: string,
}

export type Diagnostic = {
	path: string,
	rule: string,
	finding: Finding,
}

return {}
