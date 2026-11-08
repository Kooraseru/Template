-- dependencies/packages/ruleLinter/comments.luau
--!strict

local Parser = require("@std/syntax/parser")
local Syntax = require("@std/syntax")
local Visitor = require("@std/syntax/visitor")

local function visitLineComments(source: string, callback: (string, Syntax.Span) -> ())
	local parsed, file = pcall(Parser.parse, source)
	if not parsed then
		return
	end
	local seen: { [string]: boolean } = {}
	local function visitTrivia(trivia: Syntax.Trivia)
		if trivia.tag ~= "comment" then
			return
		end
		local span = trivia.location
		local key = `{span.beginLine}:{span.beginColumn}`
		if not seen[key] then
			seen[key] = true
			callback(trivia.text, span)
		end
	end
	local function visitToken(token: Syntax.CstToken): boolean
		for _, trivia in token.leadingTrivia do
			visitTrivia(trivia)
		end
		for _, trivia in token.trailingTrivia do
			visitTrivia(trivia)
		end
		return true
	end
	local visitor = Visitor.create()
	visitor.visitToken = visitToken
	Visitor.visitBlock(file.root, visitor)
	visitToken(file.eof)
end

return { VisitLineComments = visitLineComments }
