-- validation/policy.luau
--!strict

local Policy = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../libraries/registry/rules")

--# Types

export type Definition = {
	roots: { string },
	libraryRoots: { string },
	pathLabel: boolean,
	strictDirective: boolean,
	moduleNamePattern: string,
	bindingNamePattern: string,
	publicNamePattern: string,
	helperNamePattern: string,
	requiredFunctions: { string },
	forbiddenCalls: { string },
	forbiddenCasts: { string },
}

type Token = { value: string, kind: string }

--# Helpers

local function tokens(source: string): { Token }
	local result: { Token } = {}
	local cursor = 1

	local function longString(start: number): number?
		local equals = source:sub(start):match("^%[(=*)%[")

		if not equals then
			return nil
		end

		local _, finish = source:find("]" .. equals .. "]", start + #equals + 2, true)
		assert(finish, "Unterminated long string or comment")

		return finish + 1
	end

	local function scan(interpolation: boolean?)
		local braces = 0

		while cursor <= #source do
			local character = source:sub(cursor, cursor)

			if character:match("%s") then
				cursor += 1
				continue
			end

			if interpolation and character == "}" and braces == 0 then
				cursor += 1
				return
			end

			if source:sub(cursor, cursor + 1) == "--" then
				cursor = longString(cursor + 2) or source:find("\n", cursor, true) or (#source + 1)
				continue
			end

			local finish = if character == "[" then longString(cursor) else nil

			if finish then
				table.insert(result, { value = source:sub(cursor, finish - 1), kind = "string" })
				cursor = finish
				continue
			end

			if character == '"' or character == "'" or character == "`" then
				local start = cursor
				local closed = false
				cursor += 1

				while cursor <= #source do
					local current = source:sub(cursor, cursor)

					if current == "\\" then
						cursor += 2
					elseif character == "`" and current == "{" then
						cursor += 1
						scan(true)
					elseif current == character then
						cursor += 1
						closed = true
						break
					else
						cursor += 1
					end
				end

				assert(closed, "Unterminated string")
				table.insert(result, { value = source:sub(start, cursor - 1), kind = "string" })
				continue
			end

			local identifier = source:sub(cursor):match("^[A-Za-z_][A-Za-z0-9_]*")

			if identifier then
				table.insert(result, { value = identifier, kind = "identifier" })
				cursor += #identifier
				continue
			end

			if character == "{" then
				braces += 1
			elseif character == "}" then
				braces -= 1
			end

			local symbol = character

			for _, candidate in { "::", "...", ".." } do
				if source:sub(cursor, cursor + #candidate - 1) == candidate then
					symbol = candidate
					break
				end
			end

			table.insert(result, { value = symbol, kind = "symbol" })
			cursor += #symbol
		end

		assert(not interpolation, "Unterminated string interpolation")
	end

	scan()

	return result
end

local function sourceFiles(root: string, files: { string })
	if Fs.isFile(root) then
		if root:sub(-5) == ".luau" then
			table.insert(files, root)
		end

		return
	end

	assert(Fs.isDir(root), "missing policy source root: " .. root)

	for _, name in Fs.readDir(root) do
		sourceFiles(root .. "/" .. name, files)
	end
end

--# Functions

function Policy.IsLibrary(file: string, definition: Definition): boolean
	for _, root in definition.libraryRoots do
		if file == root or file:sub(1, #root + 1) == root .. "/" then
			return true
		end
	end

	return false
end

function Policy.Read(): Definition
	-- The checked-in ruleset is the configuration boundary; its cases exercise this vocabulary.
	local document = Rules.Entries(Serde.decode("json", Fs.readFile("validation/ruleset.json")))

	return Rules.Entries(document.luau).rules :: Definition
end

function Policy.CheckModule(source: string, file: string, definition: Definition): { string }
	local errors = {}
	local lines = source:gsub("\r\n", "\n"):split("\n")

	if definition.pathLabel and lines[1] ~= "-- " .. file then
		table.insert(errors, "missing repository path label")
	end

	if definition.strictDirective and lines[2] ~= "--!strict" then
		table.insert(errors, "missing strict directive")
	end

	local success, parsed = pcall(tokens, source)

	if not success then
		table.insert(errors, tostring(parsed))
		return errors
	end

	local items = parsed :: { Token }
	local values: { string } = {}

	for _, item in items do
		table.insert(values, item.value)
	end

	local function matches(index: number, expected: { string }): boolean
		for offset, value in expected do
			if values[index + offset - 1] ~= value then
				return false
			end
		end

		return true
	end

	local identity = values[2] or ""
	local declaration = matches(1, { "local", "Test", "=", "require", "(" })
		and (values[6] == '"@testing"' or values[6] == "'@testing'")
		and source:match("return%s+Test%.new") ~= nil

	if
		not declaration
		and (not matches(1, { "local", identity, "=", "{" }) or not identity:match(definition.moduleNamePattern))
	then
		table.insert(errors, "start with a named PascalCase module table")
	end

	while values[#values] == ";" do
		table.remove(values)
	end

	if not declaration and (values[#values - 1] ~= "return" or values[#values] ~= identity) then
		table.insert(errors, "return the named module table")
	end

	local functions: { [string]: boolean } = {}

	for index, item in items do
		if
			matches(index, { "function", identity, "." })
			or (matches(index, { identity, "." }) and matches(index + 3, { "=", "function" }))
		then
			local name = values[index + (if item.value == "function" then 3 else 2)] or ""
			functions[name] = true

			if name ~= "new" and not name:match(definition.publicNamePattern) then
				table.insert(errors, "public function must use PascalCase: " .. name)
			end
		end

		if
			matches(index, { "local", "function" })
			and not (values[index + 2] or ""):match(definition.helperNamePattern)
		then
			table.insert(errors, "private helper must use camelCase: " .. (values[index + 2] or ""))
		end

		if
			matches(index, { "local", values[index + 1] or "", "=", "require", "(" })
			and items[index + 5]
			and items[index + 5].kind == "string"
			and values[index + 6] == ")"
			and not table.find({ ".", ":", "[" }, values[index + 7])
			and not (values[index + 1] or ""):match(definition.bindingNamePattern)
		then
			table.insert(errors, "required module binding must use PascalCase: " .. (values[index + 1] or ""))
		end

		if
			table.find(definition.forbiddenCalls, item.value)
			and values[index + 1] == "("
			and values[index - 1] ~= "."
			and values[index - 1] ~= ":"
		then
			table.insert(errors, "logging belongs to the caller: " .. item.value)
		end

		if item.value == "::" then
			local following = index + 1

			while values[following] == "(" do
				following += 1
			end

			if table.find(definition.forbiddenCasts, values[following]) then
				table.insert(errors, "forbidden cast: " .. values[following])
			end
		end
	end

	if not declaration and not Policy.IsLibrary(file, definition) then
		for _, name in definition.requiredFunctions do
			if not functions[name] then
				table.insert(errors, "missing public function: " .. name)
			end
		end
	end

	return errors
end

function Policy.CheckRepository(definition: Definition): { string }
	local files = {}
	local failures = {}

	for _, root in definition.roots do
		sourceFiles(root, files)
	end

	assert(#files > 0, "Luau module policy selected no source files")
	table.sort(files)

	for _, file in files do
		for _, failure in Policy.CheckModule(Fs.readFile(file), file, definition) do
			table.insert(failures, file .. ": " .. failure)
		end
	end

	assert(#failures == 0, table.concat(failures, "\n"))

	return files
end

function Policy.Run()
	Policy.CheckRepository(Policy.Read())
end

return Policy
