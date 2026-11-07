-- .github/ci/components/distribution/packages/build/packageRecords.luau
--!strict

local Fs = require("@std/fs")
local Toml = require("@formats/toml")
local Process = require("@lute/process")
local Glob = require("@ci/bootstrap/discovery/glob")
local ConflictPolicy = require("@ci/integrations/github/publication/conflictPolicy")

local ROOT = ".github/distribution/packages"
local RECORD_ROOT = ".github/distribution/packages"

local PackageRecords = {}

export type Entry = {
	name: string,
	files: { string },
	description: string,
	format: string?,
	repository: string?,
	version: string?,
}
export type Records = { entries: { Entry }, onExisting: ConflictPolicy.Policy }

local function record(value: unknown, label: string): { [string]: unknown }
	if type(value) ~= "table" then
		error(`{label}: expected a table`, 0)
	end
	local result: { [string]: unknown } = {}
	for key, item in value do
		if type(key) ~= "string" then
			error(`{label}: expected named fields`, 0)
		end
		result[key] = item
	end
	return result
end

local function optionalText(value: unknown, label: string): string?
	if value == nil then
		return nil
	end
	if type(value) ~= "string" or value == "" or value:find("%c") then
		error(`{label}: expected nonempty text`, 0)
	end
	return value
end

local function regularFile(path: string): ()
	local metadata = (if Fs.exists(path) then Fs.type(path) else nil)
	if metadata == nil or metadata ~= "file" then
		error(`Expected a regular package file: {path}`, 0)
	end
	-- Reject traversal before accepting any input or description path.
	for segment in path:gmatch("[^/]+") do
		if segment == "." or segment == ".." then
			error(`Unsafe package path: {path}`, 0)
		end
	end
end

function PackageRecords.Read(): Records
	local root = record(Toml.decode(Fs.readFileToString(`{ROOT}/settings.toml`)), ROOT)
	local settings = record(root.packages, "packages")
	for field in settings do
		if field ~= "on_existing" then
			error(`{ROOT}/settings.toml: unknown shared setting {field}`, 0)
		end
	end
	local policy = ConflictPolicy.Parse(settings.on_existing, `{ROOT}/settings.toml`)
	if not Fs.exists(RECORD_ROOT) then
		return { entries = {}, onExisting = policy }
	end
	if not (Fs.exists(RECORD_ROOT) and Fs.type(RECORD_ROOT) == "dir") then
		error(`Missing package record directory: {RECORD_ROOT}`, 0)
	end
	local tracked = Process.run({ "git",  "ls-files", "--stage", "--", RECORD_ROOT })
	if not tracked.ok then
		error("Unable to inspect package record file types", 0)
	end
	for line in tracked.stdout:gmatch("[^\r\n]+") do
		if line:match("^120000%s") or line:match("^160000%s") then
			error("Package records cannot contain tracked symlinks or gitlinks", 0)
		end
	end
	local identities: { [string]: boolean } = {}
	local entries: { Entry } = {}
	for _, directory in Glob.Find(`{RECORD_ROOT}/*`) do
		-- Root policy and documentation are not package records; only directories are discovered.
		if not (Fs.exists(directory) and Fs.type(directory) == "dir") then
			continue
		end
		local name = directory:match("([^/]+)$")
		if not name or not name:match("^[%w][%w_-]*$") then
			error(`{directory}: expected a package folder with a safe identity`, 0)
		end
		if identities[name:lower()] then
			error(`Duplicate package identity: {name}`, 0)
		end
		identities[name:lower()] = true
		local path = `{directory}/package.toml`
		local description = `{directory}/description.md`
		regularFile(path)
		regularFile(description)
		if not Fs.readFileToString(description):find("%S") then
			error(`{description}: package description is empty`, 0)
		end
		local entry = record(Toml.decode(Fs.readFileToString(path)), path)
		for field in entry do
			if field ~= "files" and field ~= "format" and field ~= "repository" and field ~= "version" then
				error(`{path}: unknown package field {field}`, 0)
			end
		end
		local files = entry.files
		if type(files) ~= "table" or #files == 0 then
			error(`{path}: files must be a nonempty array`, 0)
		end
		local checked: { string } = {}
		local names: { [string]: boolean } = {}
		for index, file in files do
			if type(index) ~= "number" or type(file) ~= "string" or not file:match("^build/[%w_./%-]+$") then
				error(`{path}: files must contain safe paths under build/`, 0)
			end
			regularFile(file)
			local basename = file:match("([^/]+)$")
			if not basename or basename == "README.md" or names[basename] then
				error(`{path}: colliding staged filename {file}`, 0)
			end
			names[basename] = true
			table.insert(checked, file)
		end
		local format = optionalText(entry.format, `{path}: format`)
		if format and not format:match("^[%a][%w_-]*$") then
			error(`{path}: invalid format`, 0)
		end
		table.insert(entries, {
			name = name,
			files = checked,
			description = description,
			format = format,
			repository = optionalText(entry.repository, `{path}: repository`),
			version = optionalText(entry.version, `{path}: version`),
		})
	end
	return { entries = entries, onExisting = policy }
end

return PackageRecords
