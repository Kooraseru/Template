-- dependencies/packages/ruleLinter/discovery.luau
--!strict

local Fs = require("@lute/fs")

local function is_file(path: string): boolean
	return Fs.exists(path) and Fs.type(path) == "file"
end

local function add_validation(directory: string, entries: { string }): ()
	if not is_file(`{directory}/README.md`) then
		return
	end

	local single = `{directory}/validation.luau`
	local multiple = `{directory}/validation/init.luau`
	local has_single = is_file(single)
	local has_multiple = is_file(multiple)
	if has_single and has_multiple then
		error(`Both validation entrypoints exist in {directory}`, 0)
	end
	if has_single then
		table.insert(entries, single)
	elseif has_multiple then
		table.insert(entries, multiple)
	end
end

local function visit(directory: string, entries: { string }): ()
	local names = Fs.listdir(directory)
	table.sort(names, function(left: Fs.DirectoryEntry, right: Fs.DirectoryEntry): boolean
		return left.name < right.name
	end)
	add_validation(directory, entries)

	for _, entry in names do
		if entry.type ~= "dir" or entry.name == "tests" or entry.name == "validation" then
			continue
		end
		visit(`{directory}/{entry.name}`, entries)
	end
end

local function discover(): { string }
	local entries: { string } = {}
	local root = "rules/languages/luau"
	if not Fs.exists(root) or Fs.type(root) ~= "dir" then
		return entries
	end
	visit(root, entries)
	return entries
end

return { Discover = discover }
