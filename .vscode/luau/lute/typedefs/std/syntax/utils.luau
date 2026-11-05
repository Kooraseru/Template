-- .vscode/luau/lute/typedefs/std/syntax/utils.luau
--!strict

-- Luau LSP declaration for the Lute syntax utility module.
local syntax = require("@std/syntax")
local utils = {}

function utils.isStatLocal(_node: syntax.AstNode): boolean
	return false
end

return utils
