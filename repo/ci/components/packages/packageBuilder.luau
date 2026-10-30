-- repo/ci/components/packages/packageBuilder.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")

const CONFIG_PATH = "repo/content/packages/packages.toml"
const OUTPUT_ROOT = "build/repo/packages"

type PackageEntry = { name: string, files: { string }, format: string?, repository: string? }

local PackageBuilder = {}
PackageBuilder.__index = PackageBuilder

export type PackageBuilder = setmetatable<{}, typeof(PackageBuilder)>

local function ensureDirectory(path: string): ()
	local metadata = Fs.metadata(path)
	if metadata.kind == "symlink" then
		error(`refusing to write through a symlink: {path}`, 0)
	elseif not metadata.exists then
		Fs.writeDir(path)
	elseif metadata.kind ~= "dir" then
		error(`expected a directory at {path}`, 0)
	end
end

local function decodeEntries(): (string, { PackageEntry })
	local configuration = Serde.decode("toml", Fs.readFile(CONFIG_PATH))
	if type(configuration) ~= "table" or type(configuration.packages) ~= "table" then
		error(`{CONFIG_PATH}: expected a [packages] table`, 0)
	end
	local settings = configuration.packages
	local packageType = settings.type
	local types = settings.types
	if type(packageType) ~= "string" or type(types) ~= "table" or type(types[packageType]) ~= "table" then
		error(`{CONFIG_PATH}: packages.type must select a configured [packages.types.<type>] table`, 0)
	end
	if packageType ~= "files" then
		error(`{CONFIG_PATH}: unsupported package type {packageType}`, 0)
	end
	local entries = types[packageType].entries
	if type(entries) ~= "table" or #entries == 0 then
		error(`{CONFIG_PATH}: packages.types.{packageType} requires at least one entry`, 0)
	end
	local decoded: { PackageEntry } = {}
	local names: { [string]: boolean } = {}
	for index, entry in entries do
		if type(index) ~= "number" or type(entry) ~= "table" then
			error(`{CONFIG_PATH}: package entries must be tables`, 0)
		end
		local name = entry.name
		local files = entry.files
		local format = entry.format
		local repository = entry.repository
		if format ~= nil and (type(format) ~= "string" or not format:match("^[%a][%w_-]*$")) then
			error(`{CONFIG_PATH}: package format must be a registry format name`, 0)
		end
		if repository ~= nil and (type(repository) ~= "string" or repository == "" or repository:find("%s")) then
			error(`{CONFIG_PATH}: package repository must be owner/repository or a configured alias`, 0)
		end
		if type(name) ~= "string" or not name:match("^[%w][%w_.%-]*$") then
			error(`{CONFIG_PATH}: package {index} has an invalid name`, 0)
		end
		if names[name] then
			error(`{CONFIG_PATH}: duplicate package name {name}`, 0)
		end
		if type(files) ~= "table" or #files == 0 then
			error(`{CONFIG_PATH}: package {name} requires at least one file`, 0)
		end
		local checkedFiles: { string } = {}
		for _, path in files do
			if type(path) ~= "string" or not path:match("^build/[%w_.%-]+$") then
				error(`{CONFIG_PATH}: package {name} file paths must name a direct build output`, 0)
			end
			local metadata = Fs.metadata(path)
			if not metadata.exists or metadata.kind ~= "file" then
				error(`{CONFIG_PATH}: package {name} input is not a regular file: {path}`, 0)
			end
			table.insert(checkedFiles, path)
		end
		names[name] = true
		table.insert(decoded, { name = name, files = checkedFiles, format = format, repository = repository })
	end
	return packageType, decoded
end

function PackageBuilder.new(): PackageBuilder
	return setmetatable({}, PackageBuilder)
end

function PackageBuilder.Run(_self: PackageBuilder): ()
	local packageType, entries = decodeEntries()
	local outputMetadata = Fs.metadata(OUTPUT_ROOT)
	if outputMetadata.kind == "symlink" then
		error(`refusing to replace a symlink: {OUTPUT_ROOT}`, 0)
	elseif outputMetadata.kind == "dir" then
		Fs.removeDir(OUTPUT_ROOT)
	elseif outputMetadata.exists then
		error(`expected a directory at {OUTPUT_ROOT}`, 0)
	end
	ensureDirectory("build")
	ensureDirectory("build/repo")
	ensureDirectory(OUTPUT_ROOT)
	local index: { PackageEntry } = {}
	for _, entry in entries do
		local directory = `{OUTPUT_ROOT}/{entry.name}`
		ensureDirectory(directory)
		local outputs: { string } = {}
		for _, source in entry.files do
			local filename = source:match("([^/]+)$")
			if not filename then
				error(`invalid package file path: {source}`, 0)
			end
			local destination = `{directory}/{filename}`
			Fs.copy(source, destination)
			table.insert(outputs, `{entry.name}/{filename}`)
		end
		table.insert(
			index,
			{ name = entry.name, files = outputs, format = entry.format, repository = entry.repository }
		)
	end
	Fs.writeFile(`{OUTPUT_ROOT}/index.json`, Serde.encode("json", { type = packageType, packages = index }))
	print(`Staged {#entries} {packageType} packages into {OUTPUT_ROOT}`)
end

return PackageBuilder
