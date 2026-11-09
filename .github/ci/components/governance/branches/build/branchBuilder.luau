-- .github/ci/components/governance/branches/build/branchBuilder.luau
--!strict

local Fs = require("@std/fs")
local Toml = require("@formats/toml")
local Glob = require("@ci/bootstrap/discovery/glob")
local TagRenderer = require("@ci/rendering/tagRenderer")

local CONFIG_ROOT = ".github/governance/branches"
local CONTENT_ROOT = "docs/templates/repo"
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

local function overlayTranslations(branchRoot: string, defaultLocale: string, branchName: string): number
	local copied = 0
	for _, source in Glob.Find(`{CONTENT_ROOT}/**`) do
		if not source:match("%.md$") or (if Fs.exists(source) then Fs.type(source) else nil) ~= "file" then
			continue
		end
		local relativePath = source:gsub(`^{CONTENT_ROOT}/`, "")
		local translationStem = relativePath:gsub("%.md$", ".toml")
		for _, locale in TagRenderer.Locales() do
			if locale == defaultLocale then
				continue
			end
			local translation = `docs/i18n/{locale}/repo/{translationStem}`
			if not (Fs.exists(translation) and Fs.type(translation) == "file") then
				continue
			end
			local destination = `{branchRoot}/docs/{locale}/{relativePath}`
			local parent = destination:match("^(.*)/[^/]+$")
			if parent then
				ensureDirectory(parent)
			end
			local tags = TagRenderer.new(locale)
			local overrides = { branch_name = branchName }
			if relativePath == "README.md" then
				overrides.language_navigation = TagRenderer.LanguageNavigation(relativePath, locale)
			end
			Fs.writeStringToFile(destination, tags:Render(Fs.readFileToString(source), source, overrides))
			copied += 1
		end
	end
	return copied
end

local function copyAuthoredFile(
	source: string,
	destination: string,
	tags: TagRenderer.TagRenderer,
	branchName: string
): ()
	local parent = destination:match("^(.*)/[^/]+$")
	if parent then
		ensureDirectory(parent)
	end
	if source:match("%.md$") then
		local overrides = { branch_name = branchName }
		if source == `{CONTENT_ROOT}/README.md` then
			overrides.language_navigation = TagRenderer.LanguageNavigation("README.md", TagRenderer.DefaultLocale())
		end
		Fs.writeStringToFile(destination, tags:Render(Fs.readFileToString(source), source, overrides))
	else
		Fs.copy(source, destination)
	end
end

local function overlayTemplates(
	sourceRoot: string,
	destinationRoot: string,
	tags: TagRenderer.TagRenderer,
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
			copyAuthoredFile(source, destination, tags, branchName)
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
	TagRenderer.Validate({ CONTENT_ROOT })

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

	local defaultLocale = TagRenderer.DefaultLocale()
	local tags = TagRenderer.new(defaultLocale)
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
		copied += overlayTemplates(CONTENT_ROOT, branchRoot, tags, name)
		copied += overlayTranslations(branchRoot, defaultLocale, name)
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
