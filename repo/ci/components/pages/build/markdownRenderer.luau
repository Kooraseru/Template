-- repo/ci/components/pages/build/markdownRenderer.luau
--!strict

-- Convert one authored Markdown page to standalone HTML.
local Process = require("@lune/process")
local Pandoc = require("@workspace/dependencies/pandoc")

local MarkdownRenderer = {}
MarkdownRenderer.__index = MarkdownRenderer

type Fields = {}

export type MarkdownRenderer = setmetatable<Fields, typeof(MarkdownRenderer)>

function MarkdownRenderer.new(): MarkdownRenderer
	local fields: Fields = {}
	return setmetatable(fields, MarkdownRenderer)
end

function MarkdownRenderer.Render(_self: MarkdownRenderer, source: string, destination: string): ()
	Pandoc.Ensure()
	local result = Process.exec("pandoc", {
		"--standalone",
		"--from=gfm+yaml_metadata_block",
		"--to=html5",
		"--output",
		destination,
		source,
	})
	if not result.ok then
		error(`Pandoc failed for {source}: {result.stderr}`, 0)
	end
end

return MarkdownRenderer
