-- config/preflight/lune/sourceScanner.luau
--!strict

-- Extract module links and literal discovery globs without executing source.
local Fs = require("@lune/fs")

local SourceScanner = {}
SourceScanner.__index = SourceScanner

export type Link = {
	path: string?,
	line: number,
	column: number,
	dynamic: boolean,
}

export type Scan = {
	links: { Link },
	globs: { string },
}

export type SourceScanner = setmetatable<{}, typeof(SourceScanner)>

function SourceScanner.new(): SourceScanner
	local fields = {}
	return setmetatable(fields, SourceScanner)
end

local function skipSpace(line: string, index: number): number
	while index <= #line and line:sub(index, index):match("%s") do
		index += 1
	end
	return index
end

local function quotedValue(line: string, index: number): (string?, number)
	local quote = line:sub(index, index)
	if quote ~= "\"" and quote ~= "'" then
		return nil, index
	end

	local value: { string } = {}
	local cursor = index + 1
	while cursor <= #line do
		local character = line:sub(cursor, cursor)
		if character == quote then
			return table.concat(value), cursor + 1
		end
		if character == "\\" and cursor < #line then
			cursor += 1
			local escaped = line:sub(cursor, cursor)
			table.insert(value, if escaped == "\\" or escaped == quote then escaped else `\\{escaped}`)
		else
			table.insert(value, character)
		end
		cursor += 1
	end
	return nil, index
end

local function skipQuoted(line: string, index: number): number
	local quote = line:sub(index, index)
	local cursor = index + 1
	local escaped = false
	while cursor <= #line do
		local character = line:sub(cursor, cursor)
		if escaped then
			escaped = false
		elseif character == "\\" then
			escaped = true
		elseif character == quote then
			return cursor + 1
		end
		cursor += 1
	end
	return #line + 1
end

local function findCodeCall(line: string, pattern: string, cursor: number): (number?, number?)
	while cursor <= #line do
		local callStart, callEnd = line:find(pattern, cursor)
		local quoteStart = line:find("[\"'`]", cursor)
		if quoteStart and (not callStart or quoteStart < callStart) then
			cursor = skipQuoted(line, quoteStart)
		elseif callStart then
			return callStart, callEnd
		else
			return nil, nil
		end
	end
	return nil, nil
end

local function removeComments(line: string, longCommentEnd: string?): (string, string?)
	local fragments: { string } = {}
	local start = 1
	local quote: string? = nil
	local escaped = false
	local index = 1
	while index <= #line do
		if longCommentEnd then
			local _, closeEnd = line:find(longCommentEnd, index, true)
			if not closeEnd then
				return table.concat(fragments), longCommentEnd
			end
			table.insert(fragments, " ")
			index = closeEnd + 1
			start = index
			longCommentEnd = nil
			continue
		end

		local character = line:sub(index, index)
		if quote then
			if escaped then
				escaped = false
			elseif character == "\\" then
				escaped = true
			elseif character == quote then
				quote = nil
			end
		elseif character == "\"" or character == "'" or character == "`" then
			quote = character
		elseif character == "-" and line:sub(index, index + 1) == "--" then
			local equals = line:match("%[(=*)%[", index + 2)
			if equals then
				table.insert(fragments, line:sub(start, index - 1))
				table.insert(fragments, " ")
				index += #equals + 4
				start = index
				longCommentEnd = `]{equals}]`
				continue
			end
			table.insert(fragments, line:sub(start, index - 1))
			return table.concat(fragments), nil
		end
		index += 1
	end
	table.insert(fragments, line:sub(start))
	return table.concat(fragments), longCommentEnd
end

function SourceScanner.Scan(self: SourceScanner, source: string): Scan
	local links: { Link } = {}
	local globs: { string } = {}
	local lineNumber = 0
	local longCommentEnd: string? = nil
	local normalized = source:gsub("\r\n", "\n")
	local lines = normalized .. "\n"
	for rawLine in lines:gmatch("(.-)\n") do
		lineNumber += 1
		local line: string
		line, longCommentEnd = removeComments(rawLine, longCommentEnd)
		local cursor = 1
		while true do
			local startPosition, endPosition = findCodeCall(line, "xpcall%s*%(%s*require%s*,", cursor)
			if not startPosition or not endPosition then
				break
			end
			table.insert(links, {
				path = nil,
				line = lineNumber,
				column = startPosition,
				dynamic = true,
			})
			cursor = endPosition + 1
		end

		cursor = 1
		while true do
			local startPosition, endPosition = findCodeCall(line, "require%s*%(", cursor)
			if not startPosition or not endPosition then
				break
			end

			local argument = skipSpace(line, endPosition + 1)
			local modulePath, afterArgument = quotedValue(line, argument)
			table.insert(links, {
				path = modulePath,
				line = lineNumber,
				column = startPosition,
				dynamic = modulePath == nil,
			})
			cursor = if afterArgument > argument then afterArgument else endPosition + 1
		end

		cursor = 1
		while true do
			local startPosition, endPosition = findCodeCall(line, "Glob%s*%.%s*Find%s*%(", cursor)
			if not startPosition or not endPosition then
				break
			end
			local argument = skipSpace(line, endPosition + 1)
			local pattern = quotedValue(line, argument)
			if pattern then
				table.insert(globs, pattern)
			end
			cursor = endPosition + 1
		end
	end
	return { links = links, globs = globs }
end

function SourceScanner.Read(self: SourceScanner, path: string): Scan
	return self:Scan(Fs.readFile(path))
end

return SourceScanner
