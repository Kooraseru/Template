-- ci/content/tagRenderer.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")

const CONFIG_PATH = "config/content.toml"

type Fields = { tags: { [string]: string } }

local TagRenderer = {}
TagRenderer.__index = TagRenderer

export type TagRenderer = setmetatable<Fields, typeof(TagRenderer)>

function TagRenderer.new(): TagRenderer
	local configuration = Serde.decode("toml", Fs.readFile(CONFIG_PATH))
	if type(configuration) ~= "table" or type(configuration.tags) ~= "table" then
		error(`{CONFIG_PATH}: expected a tags table`, 0)
	end
	local tags: { [string]: string } = {}
	for name, value in configuration.tags do
		if type(name) ~= "string" or type(value) ~= "string" then
			error(`{CONFIG_PATH}: tag names and values must be strings`, 0)
		end
		tags[name] = value
	end
	local fields: Fields = { tags = tags }
	return setmetatable(fields, TagRenderer)
end

function TagRenderer.Render(
	self: TagRenderer,
	content: string,
	source: string,
	overrides: { [string]: string }?
): string
	local rendered = content:gsub("{{tag:([%w_.%-]+)}}", function(name: string): string
		local value = if overrides then overrides[name] else nil
		value = value or self.tags[name]
		if not value then
			error(`{source}: undefined content tag {name}`, 0)
		end
		return value
	end)
	if rendered:find("{{tag:", 1, true) then
		error(`{source}: malformed content tag`, 0)
	end
	return rendered
end

return TagRenderer
