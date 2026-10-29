-- repo/ci/components/pages/siteBuilder.luau
--!strict

local Fs = require("@lune/fs")

local Glob = require("@ci/bootstrap/glob")
local TagRenderer = require("@ci/content/tagRenderer")
local MarkdownRenderer = require("./markdownRenderer")
local StaticAssetCopier = require("./staticAssetCopier")

const DOCUMENTATION_ROOT = "repo/content/docs"
const OUTPUT_ROOT = "build/repo/pages"

local SiteBuilder = {}
SiteBuilder.__index = SiteBuilder

type SiteBuilderFields = {
	markdownRenderer: MarkdownRenderer.MarkdownRenderer,
	staticAssetCopier: StaticAssetCopier.StaticAssetCopier,
}

export type SiteBuilder = setmetatable<SiteBuilderFields, typeof(SiteBuilder)>

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
		local metadata = Fs.metadata(source)
		if metadata.kind == "dir" then
			ensureDirectory(destination)
		elseif metadata.kind == "file" then
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
		markdownRenderer = MarkdownRenderer.new(TagRenderer.DefaultLocale()),
		staticAssetCopier = StaticAssetCopier.new(),
	}
	return setmetatable(fields, SiteBuilder)
end

function SiteBuilder.Run(self: SiteBuilder): ()
	if not Fs.isDir(DOCUMENTATION_ROOT) then
		error(`missing documentation source directory: {DOCUMENTATION_ROOT}`, 0)
	end
	if not Fs.isFile(`{DOCUMENTATION_ROOT}/index.md`) then
		error(`documentation requires {DOCUMENTATION_ROOT}/index.md`, 0)
	end
	local TagRenderer = require("@ci/content/tagRenderer")
	TagRenderer.Validate({ DOCUMENTATION_ROOT, "repo/content/root" })

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

	renderTree(self, DOCUMENTATION_ROOT, OUTPUT_ROOT)

	if not Fs.isFile(`{OUTPUT_ROOT}/index.html`) then
		error(`Pages build did not produce {OUTPUT_ROOT}/index.html`, 0)
	end
	print(`Built documentation from {DOCUMENTATION_ROOT} into {OUTPUT_ROOT}`)
end

return SiteBuilder
