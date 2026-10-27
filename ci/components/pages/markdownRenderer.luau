-- ci/components/pages/markdownRenderer.luau
--!strict

-- Convert one authored Markdown page to standalone HTML.
local Process = require("@lune/process")

local MarkdownRenderer = {}
MarkdownRenderer.__index = MarkdownRenderer

export type MarkdownRenderer = setmetatable<{}, typeof(MarkdownRenderer)>

function MarkdownRenderer.new(): MarkdownRenderer
	return setmetatable({}, MarkdownRenderer)
end

function MarkdownRenderer.Render(self: MarkdownRenderer, source: string, destination: string): ()
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
