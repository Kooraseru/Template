-- repo/ci/components/packages/packageBuilder.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local PackageRecords = require("./packageRecords")

const OUTPUT_ROOT = "build/repo/packages"

local PackageBuilder = {}
PackageBuilder.__index = PackageBuilder
export type PackageBuilder = setmetatable<{}, typeof(PackageBuilder)>

local function ensureDirectory(path: string): ()
	local metadata = Fs.metadata(path)
	if metadata.kind == "symlink" then
		error(`Refusing to write through a symlink: {path}`, 0)
	end
	if not metadata.exists then
		Fs.writeDir(path)
	elseif metadata.kind ~= "dir" then
		error(`Expected a directory: {path}`, 0)
	end
end

function PackageBuilder.new(): PackageBuilder
	return setmetatable({}, PackageBuilder)
end

function PackageBuilder.Run(_self: PackageBuilder): ()
	local records = PackageRecords.Read()
	local metadata = Fs.metadata(OUTPUT_ROOT)
	if metadata.kind == "symlink" then
		error(`Refusing to replace a symlink: {OUTPUT_ROOT}`, 0)
	elseif metadata.kind == "dir" then
		Fs.removeDir(OUTPUT_ROOT)
	elseif metadata.exists then
		error(`Expected directory: {OUTPUT_ROOT}`, 0)
	end
	ensureDirectory("build")
	ensureDirectory("build/repo")
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
	Fs.writeFile(
		`{OUTPUT_ROOT}/index.json`,
		Serde.encode("json", { onExisting = records.onExisting, packages = index })
	)
	print(`Staged {#index} package records into {OUTPUT_ROOT}`)
end

return PackageBuilder
