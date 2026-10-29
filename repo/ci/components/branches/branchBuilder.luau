-- repo/ci/components/branches/branchBuilder.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Glob = require("@ci/bootstrap/glob")
local TagRenderer = require("@ci/content/tagRenderer")

const CONFIG_PATH = "repo/config/github.toml"
const CONTENT_ROOT = "repo/content/root"
const OUTPUT_ROOT = "build/repo/branches"

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

local function validateBranch(name: string): ()
	if not name:match("^[%w][%w_-]*$") then
		error(`{CONFIG_PATH}: invalid branch name {name}`, 0)
	end
end

local function copySource(patterns: { string }, branchRoot: string): number
	local copied = 0
	local seen: { [string]: boolean } = {}
	for _, pattern in patterns do
		if pattern == "" or pattern:sub(1, 1) == "/" or pattern:find("\\", 1, true) then
			error(`{CONFIG_PATH}: source entries must be safe repository-relative globs`, 0)
		end
		for segment in pattern:gmatch("[^/]+") do
			if segment == "." or segment == ".." then
				error(`{CONFIG_PATH}: unsafe source glob {pattern}`, 0)
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
			error(`{CONFIG_PATH}: source glob matches no files: {pattern}`, 0)
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
			local translation = `repo/content/i18n/root/{locale}/{translationStem}`
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
	local configuration = Serde.decode("toml", Fs.readFile(CONFIG_PATH))
	if type(configuration) ~= "table" or type(configuration.branches) ~= "table" then
		error(`{CONFIG_PATH}: expected a branches table`, 0)
	end
	TagRenderer.Validate({ CONTENT_ROOT, "repo/content/docs" })

	local outputMetadata = Fs.metadata(OUTPUT_ROOT)
	if outputMetadata.kind == "symlink" then
		error(`refusing to replace a symlink: {OUTPUT_ROOT}`, 0)
	elseif outputMetadata.kind == "dir" then
		Fs.removeDir(OUTPUT_ROOT)
	elseif outputMetadata.exists then
		error(`expected a directory at {OUTPUT_ROOT}`, 0)
	end
	ensureDirectory("build")
	ensureDirectory("build/repo")
	ensureDirectory(OUTPUT_ROOT)

	local defaultLocale = TagRenderer.DefaultLocale()
	local tags = TagRenderer.new(defaultLocale)
	local branchCount = 0
	for name, value in configuration.branches do
		if type(name) ~= "string" or type(value) ~= "table" or type(value.source) ~= "table" then
			error(`{CONFIG_PATH}: each branch requires a source glob array`, 0)
		end
		validateBranch(name)
		local branchRoot = `{OUTPUT_ROOT}/{name}`
		ensureDirectory(branchRoot)
		local copied = copySource(value.source, branchRoot)
		copied += overlayTemplates(CONTENT_ROOT, branchRoot, tags, name)
		copied += overlayTranslations(branchRoot, defaultLocale, name)
		if copied == 0 then
			error(`branch {name} has no source files or templates`, 0)
		end
		branchCount += 1
		print(`Built repository branch {name} with {copied} files`)
	end
	if branchCount == 0 then
		error(`{CONFIG_PATH}: no repository branches are configured`, 0)
	end
end

return BranchBuilder
