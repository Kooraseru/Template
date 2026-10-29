-- repo/ci/preflight/workspaceFiles.luau
--!strict

local Fs = require("@lune/fs")
local Glob = require("@ci/bootstrap/glob")

local WorkspaceFiles = {}

function WorkspaceFiles.Find(patterns: { string }): { string }
	local files: { string } = {}
	local excluded: { [string]: boolean } = {
		[".git"] = true,
		["build"] = true,
		["node_modules"] = true,
	}

	local function visit(directory: string)
		local absolute = if directory == "" then "." else directory
		for _, name in Fs.readDir(absolute) do
			if excluded[name] then
				continue
			end
			local path = if directory == "" then name else `{directory}/{name}`
			local metadata = Fs.metadata(path)
			if metadata.kind == "symlink" then
				continue
			end
			if metadata.kind == "dir" then
				visit(path)
				continue
			end
			if metadata.kind ~= "file" then
				continue
			end
			for _, pattern in patterns do
				if Glob.Match(path, pattern) then
					table.insert(files, path)
					break
				end
			end
		end
	end

	visit("")
	table.sort(files)
	return files
end

return WorkspaceFiles
