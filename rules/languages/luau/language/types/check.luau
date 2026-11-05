-- rules/languages/luau/language/types/check.luau
--!strict
-- rule-runner=lune

local Fs = require("@lune/fs")
local Process = require("@lune/process")

type Violation = { line: number, column: number, message: string }

local forbidden = string.char(97, 110, 121)
local pattern = "%f[%w_]" .. forbidden .. "%f[^%w_]"

local function longBracketEnd(source: string, start: number): (number?, string?)
	local equals = source:sub(start):match("^%[(=*)%[")
	if equals == nil then
		return nil, nil
	end
	local closing = "]" .. equals .. "]"
	local closeStart = source:find(closing, start + #equals + 2, true)
	return closeStart and (closeStart + #closing - 1) or #source, closing
end

-- Replace comments and strings with spaces, retaining newlines and code offsets.
local function codeOnly(source: string): string
	local output: { string } = {}
	local index = 1
	while index <= #source do
		local current = source:sub(index, index)
		local nextCharacter = source:sub(index + 1, index + 1)
		local skipUntil: number? = nil
		if current == "-" and nextCharacter == "-" then
			local longEnd = longBracketEnd(source, index + 2)
			if longEnd then
				skipUntil = longEnd
			else
				local newline = source:find("\n", index, true)
				skipUntil = newline and (newline - 1) or #source
			end
		elseif current == "'" or current == '"' or current == "`" then
			local cursor = index + 1
			while cursor <= #source do
				local character = source:sub(cursor, cursor)
				if character == "\\" then
					cursor += 2
				elseif character == current then
					break
				else
					cursor += 1
				end
			end
			skipUntil = math.min(cursor, #source)
		elseif current == "[" then
			local longEnd = longBracketEnd(source, index)
			if longEnd then
				skipUntil = longEnd
			end
		end

		if skipUntil then
			for cursor = index, skipUntil do
				local character = source:sub(cursor, cursor)
				table.insert(output, character == "\n" and "\n" or " ")
			end
			index = skipUntil + 1
		else
			table.insert(output, current)
			index += 1
		end
	end
	return table.concat(output)
end

local function check(source: string): { Violation }
	local code = codeOnly(source)
	local violations: { Violation } = {}
	local searchFrom = 1
	while true do
		local start, finish = code:find(pattern, searchFrom)
		if not start or not finish then
			break
		end
		local cursor = start - 1
		while cursor > 0 and code:sub(cursor, cursor):match("%s") do
			cursor -= 1
		end
		local before = code:sub(cursor, cursor)
		local isTypePosition = before == ":"
			or before == "="
			or before == ","
			or before == "<"
			or before == "|"
			or before == "&"
			or before == "{"
			or before == "("
		if not isTypePosition then
			searchFrom = finish + 1
			continue
		end
		local prefix = code:sub(1, start - 1)
		local lineStart = prefix:match(".*()\n") or 0
		local line = select(2, prefix:gsub("\n", "")) + 1
		table.insert(violations, {
			line = line,
			column = start - lineStart,
			message = `Do not use {forbidden} in Luau type annotations; use unknown or a specific structural type.`,
		})
		searchFrom = finish + 1
	end
	return violations
end

if Process.args[1] == "--test" then
	local base = "rules/languages/luau/language/types/tests/"
	assert(#check(Fs.readFile(base .. "valid.luau")) == 0, "valid type fixture was rejected")
	local invalid = check(Fs.readFile(base .. "invalid.luau"))
	assert(#invalid == 2, "invalid type fixture should report both forbidden annotations")
	return
end

local function scan(directory: string): { string }
	local files: { string } = {}
	for _, name in Fs.readDir(directory) do
		local file = `{directory}/{name}`
		local metadata = Fs.metadata(file)
		if metadata.kind == "symlink" then
			continue
		elseif metadata.kind == "dir" then
			if name ~= ".git" and name ~= "build" and name ~= "node_modules" then
				for _, child in scan(file) do
					table.insert(files, child)
				end
			end
		elseif name:match("%.luau$") then
			table.insert(files, file)
		end
	end
	return files
end

local files = scan(Process.args[#Process.args] or ".")
table.sort(files)
for _, file in files do
	local code = codeOnly(Fs.readFile(file))
	local searchFrom = 1
	while true do
		local start, finish = code:find(pattern, searchFrom)
		if not start or not finish then
			break
		end
		local cursor = start - 1
		while cursor > 0 and code:sub(cursor, cursor):match("%s") do
			cursor -= 1
		end
		local before = code:sub(cursor, cursor)
		local isTypePosition = before == ":"
			or before == "="
			or before == ","
			or before == "<"
			or before == "|"
			or before == "&"
			or before == "{"
			or before == "("
		if not isTypePosition then
			searchFrom = finish + 1
			continue
		end
		local prefix = code:sub(1, start - 1)
		local lineStart = prefix:match(".*()\n") or 0
		local line = select(2, prefix:gsub("\n", "")) + 1
		local column = start - lineStart
		local normalized = file:gsub("\\", "/"):gsub("^%./", "")
		print(
			`{normalized}:{line}:{column}: error: Do not use {forbidden} in Luau type annotations; use unknown or a specific structural type.`
		)
		searchFrom = finish + 1
	end
end
