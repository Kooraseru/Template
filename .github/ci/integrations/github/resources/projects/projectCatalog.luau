-- .github/ci/integrations/github/resources/projects/projectCatalog.luau
--!strict

--# Modules

local Fs = require("@std/fs")
local Json = require("@formats/json")
local Glob = require("@ci/bootstrap/discovery/glob")
local Configuration = require("@ci/integrations/github/configuration")
local Publication = require("@ci/integrations/github/publication")

--# Types

export type Option = {
	name: string,
	color: string,
	description: string,
}

export type Field = {
	name: string,
	dataType: string,
	options: { Option }?,
}

export type View = {
	name: string,
	layout: string,
	filter: string?,
	visibleFields: { string }?,
}

export type Project = {
	identity: string,
	managementKey: string,
	owner: string,
	title: string,
	description: string,
	public: boolean,
	readme: string,
	fields: { Field },
	views: { View },
}

--# Constants

local ROOT = ".github/work/projects"
local SCHEMA_PATH = `{ROOT}/project.schema.json`
local SUPPORTED_SCHEMA_KEYS = {
	"$schema",
	"$id",
	"title",
	"type",
	"additionalProperties",
	"required",
	"properties",
	"items",
	"enum",
	"minItems",
	"minLength",
}

--# Variables

local ProjectCatalog = {}

--# Helpers

local function isArray(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end

	for key in value do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
	end

	return true
end

local function array(value: unknown, label: string): { unknown }
	if not isArray(value) then
		error(`{label}: expected an array`, 0)
	end
	return value :: { unknown }
end

local function contains(values: unknown, wanted: unknown): boolean
	for _, value in array(values, "Project schema") do
		if value == wanted then
			return true
		end
	end

	return false
end

-- The runtime validator supports this explicit JSON Schema subset; fail on schema features it cannot enforce.
local function checkSchema(schema: { [string]: unknown }, path: string): ()
	-- Reject keywords this small runtime evaluator does not implement, rather than silently weakening the contract.
	for key, value in schema do
		if not contains(SUPPORTED_SCHEMA_KEYS, key) then
			error(`{path}: unsupported project schema keyword {key}`, 0)
		end

		if key == "properties" then
			for name, property in Publication.Record(value) do
				checkSchema(Publication.Record(property), `{path}.properties.{name}`)
			end
		elseif key == "items" then
			checkSchema(Publication.Record(value), `{path}.items`)
		end
	end
end

local function matchesType(value: unknown, expected: string): boolean
	if expected == "object" then
		if type(value) ~= "table" then
			return false
		end
		for key in value do
			if type(key) ~= "string" then
				return false
			end
		end
		return true
	elseif expected == "array" then
		return isArray(value)
	elseif expected == "string" or expected == "boolean" or expected == "number" or expected == "null" then
		return type(value) == expected
	end

	error(`Project schema: unsupported JSON type {expected}`, 0)
end

-- Validate the declarative shape and accepted values before applying runtime-only relationship checks.
local function validate(value: unknown, schema: { [string]: unknown }, path: string): ()
	-- Check JSON types and enum values before traversing nested objects and arrays.
	local schemaType = schema.type
	if schemaType ~= nil and type(schemaType) ~= "string" then
		error("Project schema: type must be a string", 0)
	end
	local expected = schemaType :: string?
	if expected and not matchesType(value, expected) then
		error(`{path}: expected {expected}`, 0)
	end

	if schema.enum ~= nil and not contains(schema.enum, value) then
		error(`{path}: value is not allowed by the project schema`, 0)
	end

	if expected == "object" then
		local record = Publication.Record(value)
		local properties = if schema.properties == nil then {} else Publication.Record(schema.properties)
		local required = schema.required
		-- Required properties and additionalProperties define the object boundary.
		if required ~= nil then
			if not isArray(required) then
				error("Project schema: required must be an array", 0)
			end
			for _, rawName in array(required, "Project schema required") do
				if type(rawName) ~= "string" then
					error("Project schema: required entries must be strings", 0)
				end
				local name = rawName
				if record[name] == nil then
					error(`{path}: missing required property {name}`, 0)
				end
			end
		end

		for name, item in record do
			local propertySchema = properties[name]
			if propertySchema == nil then
				if schema.additionalProperties == false then
					error(`{path}: unknown property {name}`, 0)
				end
				continue
			end
			validate(item, Publication.Record(propertySchema), `{path}.{name}`)
		end
	elseif expected == "array" then
		local values = array(value, path)
		-- Array constraints apply before each entry is recursively checked.
		if type(schema.minItems) == "number" and #values < schema.minItems then
			error(`{path}: expected at least {schema.minItems} items`, 0)
		end
		if schema.items ~= nil then
			for index, item in values do
				validate(item, Publication.Record(schema.items), `{path}[{index}]`)
			end
		end
	elseif expected == "string" then
		if type(schema.minLength) == "number" and #Publication.Text(value) < schema.minLength then
			error(`{path}: expected at least {schema.minLength} characters`, 0)
		end
	end
end

local function text(value: unknown, label: string): string
	local result = Publication.Text(value)
	if result:find("%c") then
		error(`{label}: expected single-line text`, 0)
	end
	return result
end

-- Single-select choices need uniqueness checks that JSON Schema cannot express case-insensitively.
local function fieldOptions(value: unknown, fieldName: string, path: string): { Option }
	local choices: { Option } = {}
	local seen: { [string]: boolean } = {}
	for _, item in array(value, path) do
		local option = Publication.Record(item)
		local name = text(option.name, path)
		local key = name:lower()
		if seen[key] then
			error(`{path}: duplicate option {name} for field {fieldName}`, 0)
		end
		seen[key] = true
		table.insert(choices, {
			name = name,
			color = text(option.color, path),
			description = text(option.description, path),
		})
	end
	return choices
end

local function fields(value: unknown, path: string): { Field }
	local result: { Field } = {}
	local names: { [string]: boolean } = {}
	-- JSON Schema validates each field shape; this pass checks case-insensitive uniqueness and option relationships.
	for _, item in array(value, path) do
		local entry = Publication.Record(item)
		local name = text(entry.name, path)
		local key = name:lower()
		if names[key] then
			error(`{path}: duplicate field {name}`, 0)
		end
		names[key] = true

		local dataType = Publication.Text(entry.data_type)
		local options: { Option }? = nil
		if dataType == "SINGLE_SELECT" then
			if entry.options == nil then
				error(`{path}: {name} requires options`, 0)
			end
			options = fieldOptions(entry.options, name, path)
		elseif entry.options ~= nil then
			error(`{path}: only SINGLE_SELECT accepts options`, 0)
		end

		table.insert(result, { name = name, dataType = dataType, options = options })
	end
	return result
end

local function views(value: unknown, definitions: { Field }, path: string): { View }
	if value == nil then
		return {}
	end

	local result: { View } = {}
	local names: { [string]: boolean } = {}
	local fieldNames: { [string]: boolean } = { title = true }
	-- GitHub's built-in Title field is selectable even though it is not declared in the blueprint.
	for _, field in definitions do
		fieldNames[field.name:lower()] = true
	end

	for _, item in array(value, `{path}.views`) do
		local entry = Publication.Record(item)
		local name = text(entry.name, path)
		local key = name:lower()
		if names[key] then
			error(`{path}: duplicate view {name}`, 0)
		end
		names[key] = true

		local layout = Publication.Text(entry.layout)
		if layout == "ROADMAP_LAYOUT" and entry.visible_fields ~= nil then
			error(`{path}: view {name} cannot define visible_fields for ROADMAP_LAYOUT`, 0)
		end

		local filter: string? = nil
		if entry.filter ~= nil then
			filter = text(entry.filter, path)
		end

		local configuredFields: { string }? = nil
		if entry.visible_fields ~= nil then
			configuredFields = {}
			local chosen: { [string]: boolean } = {}
			for _, rawField in array(entry.visible_fields, `{path}.views.visible_fields`) do
				if type(rawField) ~= "string" then
					error(`{path}: view {name} visible_fields must contain strings`, 0)
				end
				local field = rawField
				local fieldKey = field:lower()
				if not fieldNames[fieldKey] or chosen[fieldKey] then
					error(`{path}: view {name} references unknown or repeated field {field}`, 0)
				end
				chosen[fieldKey] = true
				table.insert(configuredFields, field)
			end
		end

		table.insert(result, { name = name, layout = layout, filter = filter, visibleFields = configuredFields })
	end
	return result
end

--# Functions

-- Read each blueprint only after the shared JSON schema has checked its declarative shape.
function ProjectCatalog.Read(): { Project }
	local schema = Publication.Record(Json.decode(Fs.readFileToString(SCHEMA_PATH)))
	checkSchema(schema, SCHEMA_PATH)

	local configuration = Configuration.new()
	local repository = configuration:ResolveRepository(configuration.repository)
	local defaultOwner = repository:match("^([^/]+)/")
	if not defaultOwner then
		error("Invalid project repository owner", 0)
	end

	local result: { Project } = {}
	local seen: { [string]: boolean } = {}
	-- Folder names provide stable identities, while the schema validates each file's declared project data.
	for _, path in Glob.Find(`{ROOT}/**/project.json`) do
		local directory = path:match("^(.*)/project%.json$")
		if not directory then
			error(`{path}: expected project.json inside a project folder`, 0)
		end

		local identity = directory:match("([^/]+)$")
		if not identity or not identity:match("^[%w][%w_-]*$") or not Fs.exists(path) or Fs.type(path) ~= "file" then
			error(`{path}: expected a project folder containing project.json`, 0)
		end
		local identityKey = identity:lower()
		if seen[identityKey] then
			error(`Duplicate project identity: {identity}`, 0)
		end
		seen[identityKey] = true

		local root = Publication.Record(Json.decode(Fs.readFileToString(path)))
		validate(root, schema, path)
		local project = Publication.Record(root.project)
		local owner = if project.owner ~= nil
			then configuration:ResolveOwner(text(project.owner, path))
			else defaultOwner

		local readmeFile = text(project.readme_file, path)
		if not readmeFile:match("^[%w_.-]+$") then
			error(`{path}: project.readme_file must name a file in its project folder`, 0)
		end
		local readme = Fs.readFileToString(`{directory}/{readmeFile}`)
		if not readme:find("%S") then
			error(`{path}: project README must contain content`, 0)
		end

		local public = project.public
		if type(public) ~= "boolean" then
			error(`{path}: project.public must be boolean`, 0)
		end

		local definitions = fields(root.fields, path)
		local configuredViews = views(root.views, definitions, path)
		table.insert(result, {
			identity = identity,
			managementKey = `{repository}:{identity}`,
			owner = owner,
			title = text(project.title, path),
			description = text(project.description, path),
			public = public,
			readme = readme,
			fields = definitions,
			views = configuredViews,
		})
	end
	return result
end

return ProjectCatalog
