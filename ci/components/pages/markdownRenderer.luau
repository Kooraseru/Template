-- ci/components/pages/markdownRenderer.luau
--!strict

-- Convert one authored Markdown page to standalone HTML.
local Process = require("@lune/process")
local Fs = require("@lune/fs")
local TagRenderer = require("@ci/content/tagRenderer")

local MarkdownRenderer = {}
MarkdownRenderer.__index = MarkdownRenderer

type Fields = { tagRenderer: TagRenderer.TagRenderer }

export type MarkdownRenderer = setmetatable<Fields, typeof(MarkdownRenderer)>

function MarkdownRenderer.new(): MarkdownRenderer
	local fields: Fields = { tagRenderer = TagRenderer.new() }
	return setmetatable(fields, MarkdownRenderer)
end

function MarkdownRenderer.Render(self: MarkdownRenderer, source: string, destination: string): ()
	local temporarySource = `{destination:gsub("%.html$", ".source.md")}`
	Fs.writeFile(temporarySource, self.tagRenderer:Render(Fs.readFile(source), source))
	local result = Process.exec("pandoc", {
		"--standalone",
		"--from=gfm+yaml_metadata_block",
		"--to=html5",
		"--output",
		destination,
		temporarySource,
	})
	Fs.removeFile(temporarySource)
	if not result.ok then
		error(`Pandoc failed for {source}: {result.stderr}`, 0)
	end
end

return MarkdownRenderer
