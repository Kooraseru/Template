-- .github/ci/components/work/labels/sync/labelCatalog.luau
--!strict

local Fs = require("@std/fs")
local Toml = require("@formats/toml")
local Yaml = require("@formats/yaml")
local Glob = require("@ci/bootstrap/discovery/glob")
local Publication = require("@ci/integrations/github/publication")

local CONFIG_PATH = ".github/work/labels.toml"
local FORM_PATTERN = ".github/ISSUE_TEMPLATE/*"

local LabelCatalog = {}
export type Label = { name: string, color: string, description: string }

function LabelCatalog.Parse(source: string): { Label }
	local root = Publication.Record(Toml.decode(source))
	for field in root do
		if field ~= "labels" then
			error(`{CONFIG_PATH}: unknown field {field}`, 0)
		end
	end
	local entries = root.labels
	if type(entries) ~= "table" then
		error(`{CONFIG_PATH}: expected [[labels]] entries`, 0)
	end
	local result: { Label } = {}
	local seen: { [string]: boolean } = {}
	for index, entry in entries do
		if type(index) ~= "number" then
			error(`{CONFIG_PATH}: labels must be an array`, 0)
		end
		local record = Publication.Record(entry)
		for field in record do
			if field ~= "name" and field ~= "color" and field ~= "description" then
				error(`{CONFIG_PATH}: unknown label field {field}`, 0)
			end
		end
		local name = Publication.Text(record.name)
		local color = Publication.Text(record.color)
		local description = record.description
		local nameLength = utf8.len(name)
		if
			not nameLength
			or nameLength > 50
			or name:find("%c")
			or name:match("^%s")
			or name:match("%s$")
			or seen[name:lower()]
		then
			error(`{CONFIG_PATH}: invalid or duplicate label name {name}`, 0)
		end
		if #color ~= 6 or not color:match("^%x+$") then
			error(`{CONFIG_PATH}: {name} color must be six hexadecimal digits without #`, 0)
		end
		if type(description) ~= "string" then
			error(`{CONFIG_PATH}: {name} description must be text`, 0)
		end
		local descriptionLength = utf8.len(description)
		if not descriptionLength or descriptionLength > 100 or description:find("%c") then
			error(`{CONFIG_PATH}: {name} description must be text of at most 100 characters`, 0)
		end
		seen[name:lower()] = true
		table.insert(result, { name = name, color = color:lower(), description = description })
	end
	table.sort(result, function(left: Label, right: Label): boolean
		return left.name < right.name
	end)
	return result
end

function LabelCatalog.ValidateForms(labels: { Label }): ()
	local declared: { [string]: boolean } = {}
	for _, label in labels do
		declared[label.name:lower()] = true
	end
	for _, path in Glob.Find(FORM_PATTERN) do
		if not path:match("%.ya?ml$") or not (Fs.exists(path) and Fs.type(path) == "file") then
			continue
		end
		local form = Publication.Record(Yaml.decode(Fs.readFileToString(path)))
		local references = form.labels
		if references == nil then
			continue
		end
		local names: { string } = {}
		if type(references) == "string" then
			for name in references:gmatch("[^,]+") do
				table.insert(names, (name:gsub("^%s+", ""):gsub("%s+$", "")))
			end
		elseif type(references) == "table" then
			for index, value in references do
				if type(index) ~= "number" or type(value) ~= "string" then
					error(`{path}: labels must be a string array`, 0)
				end
				table.insert(names, value)
			end
		else
			error(`{path}: labels must be a string array or comma-separated text`, 0)
		end
		for _, name in names do
			if not declared[name:lower()] then
				error(`{path}: label {name} is not declared in {CONFIG_PATH}`, 0)
			end
		end
	end
end

function LabelCatalog.Read(): { Label }
	local labels = LabelCatalog.Parse(Fs.readFileToString(CONFIG_PATH))
	LabelCatalog.ValidateForms(labels)
	return labels
end

return LabelCatalog
