-- .github/ci/components/documentation/pages/build/siteBuilder.luau
--!strict

local Fs = require("@std/fs")

local Glob = require("@ci/bootstrap/discovery/glob")
local MarkdownRenderer = require("./markdownRenderer")
local StaticAssetCopier = require("./staticAssetCopier")

local DOCUMENTATION_ROOT = "docs/templates/site"
local OUTPUT_ROOT = "build/github/pages"

local SiteBuilder = {}
SiteBuilder.__index = SiteBuilder

type SiteBuilderFields = {
	markdownRenderer: MarkdownRenderer.MarkdownRenderer,
	staticAssetCopier: StaticAssetCopier.StaticAssetCopier,
}

export type SiteBuilder = setmetatable<SiteBuilderFields, typeof(SiteBuilder)>

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

local function outputPath(sourcePath: string, sourceRoot: string, outputRoot: string): string
	local relativePath = sourcePath:gsub(`^{sourceRoot}/`, "")
	if relativePath:match("%.md$") then
		return `{outputRoot}/{relativePath:gsub("%.md$", ".html")}`
	end
	return `{outputRoot}/{relativePath}`
end

local function renderTree(self: SiteBuilder, sourceRoot: string, outputRoot: string): ()
	ensureDirectory(outputRoot)
	for _, source in Glob.Find(`{sourceRoot}/**`) do
		if source == sourceRoot then
			continue
		end
		local destination = outputPath(source, sourceRoot, outputRoot)
		local metadata = (if Fs.exists(source) then Fs.type(source) else nil)
		if metadata == "dir" then
			ensureDirectory(destination)
		elseif metadata == "file" then
			local parent = destination:match("^(.*)/[^/]+$")
			if parent then
				ensureDirectory(parent)
			end
			if source:match("%.md$") then
				self.markdownRenderer:Render(source, destination)
			else
				self.staticAssetCopier:Copy(source, destination)
			end
		else
			error(`unsupported documentation entry: {source}`, 0)
		end
	end
end

function SiteBuilder.new(): SiteBuilder
	local fields: SiteBuilderFields = {
		markdownRenderer = MarkdownRenderer.new(),
		staticAssetCopier = StaticAssetCopier.new(),
	}
	return setmetatable(fields, SiteBuilder)
end

function SiteBuilder.Run(self: SiteBuilder): ()
	if not (Fs.exists(DOCUMENTATION_ROOT) and Fs.type(DOCUMENTATION_ROOT) == "dir") then
		error(`missing documentation source directory: {DOCUMENTATION_ROOT}`, 0)
	end
	if not (Fs.exists(`{DOCUMENTATION_ROOT}/index.md`) and Fs.type(`{DOCUMENTATION_ROOT}/index.md`) == "file") then
		error(`documentation requires {DOCUMENTATION_ROOT}/index.md`, 0)
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

	renderTree(self, DOCUMENTATION_ROOT, OUTPUT_ROOT)

	if not (Fs.exists(`{OUTPUT_ROOT}/index.html`) and Fs.type(`{OUTPUT_ROOT}/index.html`) == "file") then
		error(`Pages build did not produce {OUTPUT_ROOT}/index.html`, 0)
	end
	print(`Built documentation from {DOCUMENTATION_ROOT} into {OUTPUT_ROOT}`)
end

return SiteBuilder
