-- repo/ci/github/projectCatalog.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Glob = require("@ci/bootstrap/glob")
local Configuration = require("@ci/github/configuration")
local Publication = require("@ci/github/publication")

const ROOT = "repo/config/projects"
const COLORS =
	{ GRAY = true, BLUE = true, GREEN = true, YELLOW = true, ORANGE = true, RED = true, PINK = true, PURPLE = true }

local ProjectCatalog = {}
export type Option = { name: string, color: string, description: string }
export type Field = { name: string, dataType: string, options: { Option }? }
export type Project = {
	identity: string,
	managementKey: string,
	owner: string,
	title: string,
	description: string,
	public: boolean,
	readme: string,
	fields: { Field },
}

local function known(record: { [string]: unknown }, allowed: { [string]: boolean }, label: string): ()
	for key in record do
		if not allowed[key] then
			error(`{label}: unknown field {key}`, 0)
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

local function fields(value: unknown, path: string): { Field }
	if type(value) ~= "table" then
		error(`{path}: expected [[fields]] definitions`, 0)
	end
	local result: { Field } = {}
	local names: { [string]: boolean } = {}
	for index, item in value do
		if type(index) ~= "number" then
			error(`{path}: fields must be an array`, 0)
		end
		local entry = Publication.Record(item)
		known(entry, { name = true, data_type = true, options = true }, path)
		local name = text(entry.name, path)
		local dataType = text(entry.data_type, path)
		if names[name:lower()] then
			error(`{path}: duplicate field {name}`, 0)
		end
		names[name:lower()] = true
		if dataType ~= "TEXT" and dataType ~= "NUMBER" and dataType ~= "DATE" and dataType ~= "SINGLE_SELECT" then
			error(`{path}: unsupported blueprint field type {dataType}`, 0)
		end
		local options: { Option }? = nil
		if dataType == "SINGLE_SELECT" then
			local source = entry.options
			if type(source) ~= "table" or #source == 0 then
				error(`{path}: {name} requires options`, 0)
			end
			local choices: { Option } = {}
			local seen: { [string]: boolean } = {}
			for key, choice in source do
				if type(key) ~= "number" then
					error(`{path}: options must be an array`, 0)
				end
				local option = Publication.Record(choice)
				known(option, { name = true, color = true, description = true }, path)
				local optionName = text(option.name, path)
				local color = text(option.color, path)
				local description = text(option.description, path)
				if seen[optionName:lower()] or not COLORS[color] then
					error(`{path}: duplicate option or invalid option color`, 0)
				end
				seen[optionName:lower()] = true
				table.insert(choices, { name = optionName, color = color, description = description })
			end
			options = choices
		elseif entry.options ~= nil then
			error(`{path}: only SINGLE_SELECT accepts options`, 0)
		end
		table.insert(result, { name = name, dataType = dataType, options = options })
	end
	return result
end

function ProjectCatalog.Read(): { Project }
	local configuration = Configuration.new()
	local repository = configuration:ResolveRepository(configuration.repository)
	local defaultOwner = repository:match("^([^/]+)/")
	if not defaultOwner then
		error("Invalid project repository owner", 0)
	end
	local result: { Project } = {}
	local seen: { [string]: boolean } = {}
	for _, directory in Glob.Find(`{ROOT}/*`) do
		if directory == `{ROOT}/README.md` or directory == `{ROOT}/.gitkeep` then
			continue
		end
		local identity = directory:match("([^/]+)$")
		if not identity or not identity:match("^[%w][%w_-]*$") or not Fs.isDir(directory) then
			error(`{directory}: expected a project folder`, 0)
		end
		if seen[identity:lower()] then
			error(`Duplicate project identity: {identity}`, 0)
		end
		seen[identity:lower()] = true
		local path = `{directory}/project.toml`
		local root = Publication.Record(Serde.decode("toml", Fs.readFile(path)))
		known(root, { project = true, fields = true }, path)
		local project = Publication.Record(root.project)
		known(project, { owner = true, title = true, description = true, public = true }, path)
		local owner = if project.owner ~= nil
			then configuration:ResolveOwner(text(project.owner, path))
			else defaultOwner
		local public = project.public
		if type(public) ~= "boolean" then
			error(`{path}: project.public must be boolean`, 0)
		end
		local readme = Fs.readFile(`{directory}/README.md`)
		if not readme:find("%S") then
			error(`{directory}: README.md must describe the project`, 0)
		end
		table.insert(result, {
			identity = identity,
			managementKey = `{repository}:{identity}`,
			owner = owner,
			title = text(project.title, path),
			description = text(project.description, path),
			public = public,
			readme = readme,
			fields = fields(root.fields, path),
		})
	end
	return result
end

return ProjectCatalog
