-- rules/languages/luau/files/path-headers/check.luau
--!strict
-- rule-runner=lune

local Fs = require("@lune/fs")
local Process = require("@lune/process")

type Violation = { line: number, message: string }

local function check(path: string, source: string): { Violation }
	local lines = string.split(source, "\n")
	for index, line in lines do
		lines[index] = line:gsub("\r$", "")
	end
	local violations: { Violation } = {}
	local normalized = path:gsub("\\", "/"):gsub("^%./", ""):gsub("\r$", "")
	if lines[1] ~= `-- {normalized}` then
		table.insert(violations, { line = 1, message = `expected path header '-- {normalized}'` })
	end
	if lines[2] ~= "--!strict" then
		table.insert(violations, { line = 2, message = "expected --!strict after the path header" })
	end
	return violations
end

if Process.args[1] == "--test" then
	local valid = check(
		"rules/languages/luau/files/path-headers/tests/valid.luau",
		Fs.readFile("rules/languages/luau/files/path-headers/tests/valid.luau")
	)
	local invalid = check(
		"rules/languages/luau/files/path-headers/tests/invalid.luau",
		Fs.readFile("rules/languages/luau/files/path-headers/tests/invalid.luau")
	)
	assert(#valid == 0, "valid fixture was rejected")
	assert(#invalid == 2, "invalid fixture did not report both header violations")
	return
end

local root = Process.args[#Process.args] or "."
local function scan(directory: string): { string }
	local files: { string } = {}
	for _, name in Fs.readDir(directory) do
		local path = `{directory}/{name}`
		local metadata = Fs.metadata(path)
		if metadata.kind == "symlink" then
			continue
		end
		if metadata.kind == "dir" then
			if name ~= ".git" and name ~= "build" and name ~= "node_modules" then
				for _, child in scan(path) do
					table.insert(files, child)
				end
			end
		elseif name:match("%.luau$") then
			table.insert(files, path)
		end
	end
	return files
end

local failures = 0
local files = scan(root)
table.sort(files)
for _, file in files do
	local normalized = file:gsub("\\", "/"):gsub("^%./", "")
	for _, violation in check(normalized, Fs.readFile(file)) do
		print(`{normalized}:{violation.line}:1: error: {violation.message}`)
		failures += 1
	end
end
