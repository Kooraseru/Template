-- rules/languages/bash/files/scripts/check.luau
--!strict
-- rule-runner=lune

local Fs = require("@lune/fs")
local Process = require("@lune/process")

local function valid(source: string): boolean
	return source:match("^#!/usr/bin/env bash[\r]?\n") ~= nil
end

if Process.args[1] == "--test" then
	assert(valid(Fs.readFile("rules/languages/bash/files/scripts/tests/valid.sh")), "valid script was rejected")
	assert(not valid(Fs.readFile("rules/languages/bash/files/scripts/tests/invalid.sh")), "invalid script was accepted")
	return
end

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
		elseif name:match("%.sh$") then
			table.insert(files, path)
		end
	end
	return files
end

local files = scan(Process.args[#Process.args] or ".")
table.sort(files)
for _, file in files do
	if not valid(Fs.readFile(file)) then
		print(`{file}:1:1: error: Bash scripts must start with #!/usr/bin/env bash`)
	end
end
