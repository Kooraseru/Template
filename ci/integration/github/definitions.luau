-- ci/integration/github/definitions.luau
--!strict

local Definitions = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Shape = require("../../utilities/shape")

--# Types

export type Field = { name: string, dataType: string, options: { string } }
export type View = { name: string, layout: string }
export type Automation = { event: string, action: string, labels: { string } }
export type Project = {
	slug: string,
	title: string,
	description: string,
	visibility: string,
	mode: string,
	fields: { Field },
	views: { View },
	automations: { Automation },
}
export type Label = { name: string, color: string, description: string }

--# Helpers

local function document(path: string, allowed: { string }): Shape.Object
	assert(Fs.isFile(path), "missing declaration: " .. path)
	return Shape.Object(Serde.decode("toml", Fs.readFile(path)), allowed)
end

local function stringValue(value: unknown, label: string): string
	return Shape.Text(value, label)
end

local function oneOf(value: unknown, label: string, choices: { string }): string
	local selected = stringValue(value, label)
	assert(table.find(choices, selected), "unsupported " .. label .. ": " .. selected)
	return selected
end

-- Only lowercase folder names establish identity; no registry or numeric schema.
local function slug(value: string): string
	assert(value:match("^[a-z][a-z0-9%-]*$"), "invalid lowercase name: " .. value)
	return value
end

local function folders(path: string): { string }
	if not Fs.isDir(path) then
		return {}
	end
	local result = {}
	for _, name in Fs.readDir(path) do
		if Fs.isDir(path .. "/" .. name) then
			table.insert(result, slug(name))
		elseif name ~= "README.md" then
			error("unexpected configuration file: " .. path .. "/" .. name)
		end
	end
	table.sort(result)
	return result
end

local function tomls(path: string): { string }
	if not Fs.isDir(path) then
		return {}
	end
	local result = {}
	for _, name in Fs.readDir(path) do
		if name ~= "README.md" then
			assert(Fs.isFile(path .. "/" .. name), "configuration must be a regular file: " .. name)
			local key = name:match("^([a-z][a-z0-9%-]*)%.toml$")
			assert(key ~= nil, "unexpected configuration entry: " .. path .. "/" .. name)
			table.insert(result, name)
		end
	end
	table.sort(result)
	return result
end

local function optionalTomls(path: string): { string }
	if not Fs.isDir(path) then
		return {}
	end
	return tomls(path)
end

local function unique(name: string, seen: { [string]: boolean }, kind: string)
	assert(not seen[name], "duplicate " .. kind .. ": " .. name)
	seen[name] = true
end

--# Functions

function Definitions.ReadProjects(source: string?): { Project }
	local root = source or ".github/projects"
	local result: { Project } = {}

	for _, name in folders(root) do
		local path = root .. "/" .. name
		local projectSettings = document(path .. "/project.toml", { "title", "description", "visibility", "mode" })
		local project: Project = {
			slug = name,
			title = stringValue(projectSettings.title, "project title"),
			description = stringValue(projectSettings.description, "project description"),
			visibility = oneOf(projectSettings.visibility, "project visibility", { "public", "private" }),
			mode = oneOf(projectSettings.mode, "project mode", { "managed", "template" }),
			fields = {},
			views = {},
			automations = {},
		}

		local fieldNames: { [string]: boolean } = {}
		for _, file in optionalTomls(path .. "/fields") do
			local settings = document(path .. "/fields/" .. file, { "name", "type", "options" })
			local fieldName = stringValue(settings.name, "field name")
			local dataType = oneOf(settings.type, "field type", { "single_select", "text", "number", "date" })
			unique(fieldName, fieldNames, "project field")
			local options: { string } = if settings.options then Shape.Strings(settings.options, "option") else {}
			assert((dataType == "single_select") == (#options > 0), "invalid options for " .. fieldName)
			local field: Field = { name = fieldName, dataType = dataType, options = options }
			table.insert(project.fields, field)
		end

		local viewNames: { [string]: boolean } = {}
		for _, file in optionalTomls(path .. "/views") do
			local settings = document(path .. "/views/" .. file, { "name", "layout" })
			local viewName = stringValue(settings.name, "view name")
			unique(viewName, viewNames, "project view")
			table.insert(project.views, {
				name = viewName,
				layout = oneOf(settings.layout, "view layout", { "table", "board", "roadmap" }),
			})
		end

		for _, file in optionalTomls(path .. "/automations") do
			local settings = document(path .. "/automations/" .. file, { "event", "action", "labels" })
			local event = oneOf(settings.event, "automation event", {
				"issues.opened",
				"issues.labeled",
				"pull_request.opened",
			})
			local action = oneOf(settings.action, "automation action", { "add_item" })
			local labels = Shape.Strings(settings.labels or {}, "automation label")
			assert(not (event == "pull_request.opened" and #labels > 0), "PR intake cannot filter issue labels")
			table.insert(project.automations, { event = event, action = action, labels = labels })
		end

		table.insert(result, project)
	end

	return result
end

function Definitions.ReadLabels(source: string?): { Label }
	local result: { Label } = {}
	local names: { [string]: boolean } = {}
	local root = source or ".github/labels"
	for _, file in tomls(root) do
		local settings = document(root .. "/" .. file, { "name", "color", "description" })
		local name = stringValue(settings.name, "label name")
		unique(name, names, "label")
		assert(name == file:sub(1, -6), "label filename must match its name")
		local color = stringValue(settings.color, "label color")
		assert(color:match("^[%x]+$") and #color == 6, "expected six-digit hex color")
		table.insert(
			result,
			{ name = name, color = color, description = stringValue(settings.description, "label description") }
		)
	end
	return result
end

return Definitions
