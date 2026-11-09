-- ci/components/distribution/packages/build/packageBuilder.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local PackageRecords = require("./packageRecords")

local OUTPUT_ROOT = "build/github/packages"

local PackageBuilder = {}
PackageBuilder.__index = PackageBuilder
export type PackageBuilder = setmetatable<{}, typeof(PackageBuilder)>

local function ensureDirectory(path: string): ()
	local metadata = (if Fs.exists(path) then Fs.type(path) else nil)
	if metadata == "link" then
		error(`Refusing to write through a symlink: {path}`, 0)
	end
	if metadata == nil then
		Fs.createDirectory(path, { makeParents = true })
	elseif metadata ~= "dir" then
		error(`Expected a directory: {path}`, 0)
	end
end

function PackageBuilder.new(): PackageBuilder
	return setmetatable({}, PackageBuilder)
end

function PackageBuilder.Run(_self: PackageBuilder): string?
	local records = PackageRecords.Read()
	local metadata = (if Fs.exists(OUTPUT_ROOT) then Fs.type(OUTPUT_ROOT) else nil)
	if metadata == "link" then
		error(`Refusing to replace a symlink: {OUTPUT_ROOT}`, 0)
	elseif metadata == "dir" then
		Fs.removeDirectory(OUTPUT_ROOT, { recursive = true })
	elseif metadata ~= nil then
		error(`Expected directory: {OUTPUT_ROOT}`, 0)
	end
	if #records.entries == 0 then
		print("Packages skipped: no package records")
		return "skipped"
	end
	ensureDirectory("build")
	ensureDirectory("build/github")
	ensureDirectory(OUTPUT_ROOT)
	local index: { PackageRecords.Entry } = {}
	for _, entry in records.entries do
		local directory = `{OUTPUT_ROOT}/{entry.name}`
		ensureDirectory(directory)
		local files: { string } = {}
		for _, source in entry.files do
			local filename = source:match("([^/]+)$")
			if not filename then
				error(`Invalid package file: {source}`, 0)
			end
			Fs.copy(source, `{directory}/{filename}`)
			table.insert(files, `{entry.name}/{filename}`)
		end
		Fs.copy(entry.description, `{directory}/README.md`)
		table.insert(index, {
			name = entry.name,
			files = files,
			description = `{entry.name}/README.md`,
			format = entry.format,
			repository = entry.repository,
			version = entry.version,
		})
	end
	Fs.writeStringToFile(
		`{OUTPUT_ROOT}/index.json`,
		Json.encode({ onExisting = records.onExisting, packages = index })
	)
	print(`Staged {#index} package records into {OUTPUT_ROOT}`)
	return nil
end

return PackageBuilder
