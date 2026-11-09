-- dependencies/packages/checks/ruleLinter/phaseLayout.luau
--!strict

local Syntax = require("@std/syntax")

local function spansFiveLines(statement: Syntax.CstStat): boolean
	return statement.location.endLine - statement.location.beginLine >= 4
end

local function isExit(statement: Syntax.CstStat): boolean
	return statement.tag == "return" or statement.tag == "break" or statement.tag == "continue"
end

local function isControlPhase(statement: Syntax.CstStat): boolean
	if not spansFiveLines(statement) then
		return false
	end
	if statement.tag == "conditional" then
		local body = statement.thenBlock.statements
		return #statement.elseifs > 0 or statement.elseBlock ~= nil or #body ~= 1 or not isExit(body[1])
	end
	return statement.tag == "for" or statement.tag == "forin" or statement.tag == "while"
		or statement.tag == "repeat" or statement.tag == "do"
end

local function isStructured(statement: Syntax.CstStat): boolean
	return isControlPhase(statement) or (spansFiveLines(statement)
		and (statement.tag == "function" or statement.tag == "localfunction"))
end

local function isShortExit(statement: Syntax.CstStat): boolean
	return isExit(statement) and statement.location.beginLine == statement.location.endLine
end

return { IsControlPhase = isControlPhase, IsStructured = isStructured, IsShortExit = isShortExit }
