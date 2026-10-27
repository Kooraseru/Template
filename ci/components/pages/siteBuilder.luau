-- ci/components/pages/siteBuilder.luau
--!strict

-- Assemble the docs tree into the static site artifact consumed by publication.
local Fs = require("@lune/fs")

local Glob = require("@ci/bootstrap/glob")
local MarkdownRenderer = require("./markdownRenderer")
local StaticAssetCopier = require("./staticAssetCopier")

const DOCUMENTATION_ROOT = "docs"
const OUTPUT_ROOT = "build/pages"

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

local function outputPath(sourcePath: string): string
	local relativePath = sourcePath:gsub(`^{DOCUMENTATION_ROOT}/`, "")
	if relativePath:match("%.md$") then
		return `{OUTPUT_ROOT}/{relativePath:gsub("%.md$", ".html")}`
	end
	return `{OUTPUT_ROOT}/{relativePath}`
end

function SiteBuilder.new(): SiteBuilder
	local fields: SiteBuilderFields = {
		markdownRenderer = MarkdownRenderer.new(),
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

	local outputMetadata = Fs.metadata(OUTPUT_ROOT)
	if outputMetadata.kind == "symlink" then
		error(`refusing to replace a symlink: {OUTPUT_ROOT}`, 0)
	elseif outputMetadata.kind == "dir" then
		Fs.removeDir(OUTPUT_ROOT)
	elseif outputMetadata.exists then
		error(`expected a directory at {OUTPUT_ROOT}`, 0)
	end
	ensureDirectory(OUTPUT_ROOT)

	for _, source in Glob.Find(`{DOCUMENTATION_ROOT}/**`) do
		if source == DOCUMENTATION_ROOT then
			continue
		end
		local metadata = Fs.metadata(source)
		if metadata.kind == "dir" then
			ensureDirectory(outputPath(source))
		elseif metadata.kind == "file" then
			local destination = outputPath(source)
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

	if not Fs.isFile(`{OUTPUT_ROOT}/index.html`) then
		error("Pages build did not produce build/pages/index.html", 0)
	end
	print(`Built documentation from {DOCUMENTATION_ROOT} into {OUTPUT_ROOT}`)
end

return SiteBuilder
