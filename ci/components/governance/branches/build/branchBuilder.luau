-- ci/components/governance/branches/build/branchBuilder.luau
--!strict

local Fs = require("@std/fs")
local Toml = require("@formats/toml")
local Glob = require("@ci/bootstrap/discovery/glob")
local Process = require("@lute/process")

local CONFIG_ROOT = ".github/config/branches"
local CONTENT_ROOT = "content/docs/repository"
local OUTPUT_ROOT = "build/github/branches"

local BranchBuilder = {}
BranchBuilder.__index = BranchBuilder

export type BranchBuilder = setmetatable<{}, typeof(BranchBuilder)>

local function ensureDirectory(path: string): ()
	local metadata = (if Fs.exists(path) then Fs.type(path) else nil)
	if metadata == "link" then
		error(`refusing to write through a symlink: {path}`, 0)
	end
	if metadata == nil then
		Fs.createDirectory(path, { makeParents = true })
	elseif metadata ~= "dir" then
		error(`expected a directory at {path}`, 0)
	end
end

local function validateBranch(name: string, path: string): ()
	if not name:match("^[%w][%w_-]*$") then
		error(`{path}: invalid branch name {name}`, 0)
	end
end

local function copySource(patterns: { string }, branchRoot: string, recordPath: string): number
	local copied = 0
	local seen: { [string]: boolean } = {}
	for _, pattern in patterns do
		if pattern == "" or pattern:sub(1, 1) == "/" or pattern:find("\\", 1, true) then
			error(`{recordPath}: source entries must be safe repository-relative globs`, 0)
		end

		for segment in pattern:gmatch("[^/]+") do
			if segment == "." or segment == ".." then
				error(`{recordPath}: unsafe source glob {pattern}`, 0)
			end
		end

		local matched = false

		for _, source in Glob.Find(pattern) do
			local metadata = (if Fs.exists(source) then Fs.type(source) else nil)
			if metadata == "dir" then
				continue
			elseif metadata ~= "file" then
				error(`unsupported repository source entry: {source}`, 0)
			end
			matched = true
			if source == ".gitkeep" or source:match("/%.gitkeep$") or seen[source] then
				continue
			end
			seen[source] = true
			local destination = `{branchRoot}/{source}`
			local parent = destination:match("^(.*)/[^/]+$")
			if parent then
				ensureDirectory(parent)
			end
			Fs.copy(source, destination)
			copied += 1
		end
		if not matched then
			error(`{recordPath}: source glob matches no files: {pattern}`, 0)
		end
	end
	return copied
end

-- Repository documents use explicit English placeholders, independent of site i18n.
local function renderTemplate(content: string, source: string, branchName: string): string
	local repository = Process.env.GITHUB_REPOSITORY or ""
	local projectName = repository:match("^[%w_.-]+/([%w_.-]+)$") or "Project"
	local values = {
		["project.name"] = projectName,
		["branch.name"] = branchName,
		["branch.source"] = "source",
	}
	local rendered = content:gsub("{{([%w_.-]+)}}", function(key: string): string
		return values[key] or error(`{source}: unknown repository placeholder {key}`, 0)
	end)
	if rendered:find("{{", 1, true) then
		error(`{source}: invalid repository template placeholder`, 0)
	end
	return rendered
end

local function copyAuthoredFile(source: string, destination: string, branchName: string): ()
	local parent = destination:match("^(.*)/[^/]+$")
	if parent then ensureDirectory(parent) end
	if source:match("%.md$") then
		Fs.writeStringToFile(destination, renderTemplate(Fs.readFileToString(source), source, branchName))
	else
		Fs.copy(source, destination)
	end
end

local function overlayTemplates(
	sourceRoot: string,
	destinationRoot: string,
	branchName: string
): number
	local copied = 0
	for _, source in Glob.Find(`{sourceRoot}/**`) do
		if source == sourceRoot then
			continue
		end
		local relativePath = source:gsub(`^{sourceRoot}/`, "")
		local destination = `{destinationRoot}/{relativePath}`
		local metadata = (if Fs.exists(source) then Fs.type(source) else nil)
		if metadata == "dir" then
			ensureDirectory(destination)
		elseif metadata == "file" then
			copyAuthoredFile(source, destination, branchName)
			copied += 1
		else
			error(`unsupported authored template entry: {source}`, 0)
		end
	end
	return copied
end

function BranchBuilder.new(): BranchBuilder
	return setmetatable({}, BranchBuilder)
end

function BranchBuilder.Run(_self: BranchBuilder): ()
	if not (Fs.exists(CONTENT_ROOT) and Fs.type(CONTENT_ROOT) == "dir") then
		error(`missing repository content directory: {CONTENT_ROOT}`, 0)
	end

	local outputMetadata = (if Fs.exists(OUTPUT_ROOT) then Fs.type(OUTPUT_ROOT) else nil)
	if outputMetadata == "link" then
		error(`refusing to replace a symlink: {OUTPUT_ROOT}`, 0)
	elseif outputMetadata == "dir" then
		Fs.removeDirectory(OUTPUT_ROOT, { recursive = true })
	elseif outputMetadata ~= nil then
		error(`expected a directory at {OUTPUT_ROOT}`, 0)
	end
	ensureDirectory("build")
	ensureDirectory("build/github")
	ensureDirectory(OUTPUT_ROOT)

	local branchCount = 0
	local records = Glob.Find(`{CONFIG_ROOT}/*.toml`)
	table.sort(records)
	for _, path in records do
		if (if Fs.exists(path) then Fs.type(path) else nil) ~= "file" then
			error(`{path}: branch record must be a regular file`, 0)
		end
		local name = path:match("([^/]+)%.toml$")
		if not name then
			error(`{path}: branch record filename must end in .toml`, 0)
		end
		validateBranch(name, path)
		local configuration = Toml.decode(Fs.readFileToString(path))
		if type(configuration) ~= "table" or type(configuration.branch) ~= "table" then
			error(`{path}: expected a [branch] table`, 0)
		end
		local value = configuration.branch
		if type(value.source) ~= "table" then
			error(`{path}: branch requires a source glob array`, 0)
		end
		local branchRoot = `{OUTPUT_ROOT}/{name}`
		ensureDirectory(branchRoot)
		local sources: { string } = {}
		for _, source in value.source :: { unknown } do
			if type(source) ~= "string" then error(`{path}: source globs must be strings`, 0) end
			table.insert(sources, source)
		end
		local copied = copySource(sources, branchRoot, path)
		copied += overlayTemplates(CONTENT_ROOT, branchRoot, name)
		if copied == 0 then
			error(`branch {name} has no source files or templates`, 0)
		end
		branchCount += 1
		print(`Built repository branch {name} with {copied} files`)
	end
	if branchCount == 0 then
		print(`No repository branches are configured under {CONFIG_ROOT}`)
	end
end

return BranchBuilder
