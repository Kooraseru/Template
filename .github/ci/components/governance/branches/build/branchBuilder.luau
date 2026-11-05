-- .github/ci/components/governance/branches/build/branchBuilder.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Glob = require("@ci/bootstrap/discovery/glob")
local TagRenderer = require("@ci/rendering/tagRenderer")

const CONFIG_ROOT = ".github/governance/branches"
const CONTENT_ROOT = "docs/templates/repo"
const OUTPUT_ROOT = "build/github/branches"

local BranchBuilder = {}
BranchBuilder.__index = BranchBuilder

export type BranchBuilder = setmetatable<{}, typeof(BranchBuilder)>

local function ensureDirectory(path: string): ()
	local metadata = Fs.metadata(path)
	if metadata.kind == "symlink" then
		error(`refusing to write through a symlink: {path}`, 0)
	end
	if not metadata.exists then
		Fs.writeDir(path)
	elseif metadata.kind ~= "dir" then
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
			local metadata = Fs.metadata(source)
			if metadata.kind == "dir" then
				continue
			elseif metadata.kind ~= "file" then
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
		if not source:match("%.md$") or Fs.metadata(source).kind ~= "file" then
			continue
		end
		local relativePath = source:gsub(`^{CONTENT_ROOT}/`, "")
		local translationStem = relativePath:gsub("%.md$", ".toml")
		for _, locale in TagRenderer.Locales(nil) do
			if locale == defaultLocale then
				continue
			end
			local translation = `docs/i18n/{locale}/repo/{translationStem}`
			if not Fs.isFile(translation) then
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
			Fs.writeFile(destination, tags:Render(Fs.readFile(source), source, overrides))
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
		Fs.writeFile(destination, tags:Render(Fs.readFile(source), source, overrides))
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
		local metadata = Fs.metadata(source)
		if metadata.kind == "dir" then
			ensureDirectory(destination)
		elseif metadata.kind == "file" then
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
	if not Fs.isDir(CONTENT_ROOT) then
		error(`missing repository content directory: {CONTENT_ROOT}`, 0)
	end
	TagRenderer.Validate({ CONTENT_ROOT })

	local outputMetadata = Fs.metadata(OUTPUT_ROOT)
	if outputMetadata.kind == "symlink" then
		error(`refusing to replace a symlink: {OUTPUT_ROOT}`, 0)
	elseif outputMetadata.kind == "dir" then
		Fs.removeDir(OUTPUT_ROOT)
	elseif outputMetadata.exists then
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
		if Fs.metadata(path).kind ~= "file" then
			error(`{path}: branch record must be a regular file`, 0)
		end
		local name = path:match("([^/]+)%.toml$")
		if not name then
			error(`{path}: branch record filename must end in .toml`, 0)
		end
		validateBranch(name, path)
		local configuration = Serde.decode("toml", Fs.readFile(path))
		if type(configuration) ~= "table" or type(configuration.branch) ~= "table" then
			error(`{path}: expected a [branch] table`, 0)
		end
		local value = configuration.branch
		if type(value.source) ~= "table" then
			error(`{path}: branch requires a source glob array`, 0)
		end
		local branchRoot = `{OUTPUT_ROOT}/{name}`
		ensureDirectory(branchRoot)
		local copied = copySource(value.source, branchRoot, path)
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
