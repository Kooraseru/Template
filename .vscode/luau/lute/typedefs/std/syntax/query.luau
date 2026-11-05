-- .vscode/luau/lute/typedefs/std/syntax/query.luau
--!strict

-- Luau LSP declaration for the Lute syntax query module.
local syntax = require("@std/syntax")
local query = {}

function query.findAllFromRoot(
	_root: syntax.AstStatBlock,
	_predicate: (node: syntax.AstNode) -> boolean
): { nodes: { syntax.AstStatLocal } }
	return { nodes = {} }
end

return query
