-- repo/ci/components/pages/markdownRenderer.luau
--!strict

-- Convert one authored Markdown page to standalone HTML.
local Process = require("@lune/process")
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local TagRenderer = require("@ci/content/tagRenderer")
local Pandoc = require("@ci/dependencies/pandoc")

local MarkdownRenderer = {}
MarkdownRenderer.__index = MarkdownRenderer

type Fields = { tagRenderer: TagRenderer.TagRenderer }

export type MarkdownRenderer = setmetatable<Fields, typeof(MarkdownRenderer)>

function MarkdownRenderer.new(locale: string): MarkdownRenderer
	local fields: Fields = { tagRenderer = TagRenderer.new(locale) }
	return setmetatable(fields, MarkdownRenderer)
end

function MarkdownRenderer.Render(self: MarkdownRenderer, source: string, destination: string): ()
	Pandoc.Ensure()
	local temporarySource = `{destination:gsub("%.html$", ".source.md")}`
	local temporaryInclude = `{destination:gsub("%.html$", ".locale.html")}`
	local catalog = Serde.encode("json", self.tagRenderer:PageData(source)):gsub("<", "\\u003c")
	local localeScript = Fs.readFile("repo/ci/components/pages/locale.js")
	Fs.writeFile(
		temporaryInclude,
		`<script>window.__PAGE_I18N__ = {catalog};</script>\n<script>\n{localeScript}\n</script>`
	)
	Fs.writeFile(temporarySource, self.tagRenderer:Render(Fs.readFile(source), source, nil, true))
	local result = Process.exec("pandoc", {
		"--standalone",
		"--from=gfm+yaml_metadata_block",
		"--to=html5",
		"--output",
		destination,
		"--include-after-body",
		temporaryInclude,
		temporarySource,
	})
	Fs.removeFile(temporarySource)
	Fs.removeFile(temporaryInclude)
	if not result.ok then
		error(`Pandoc failed for {source}: {result.stderr}`, 0)
	end
end

return MarkdownRenderer
