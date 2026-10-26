-- ci/bootstrap/discovery.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")

local Contract = require("./contract")
local Glob = require("./glob")

local Discovery = {}
Discovery.__index = Discovery

export type Discovery = setmetatable<{}, typeof(Discovery)>

function Discovery.new(): Discovery
	local fields = {}
	return setmetatable(fields, Discovery)
end

-- Lune's filesystem metadata follows symlinks on supported releases. The
-- checked-out Git tree supplies the authoritative type of tracked entries;
-- reject links before walking a discovered extension point.
function Discovery.RejectLinkedEntries(self: Discovery): ()
	local result = Process.exec("git", { "ls-files", "--stage", "--", "ci/components" })
	if not result.ok then
		error(`unable to inspect tracked component entry types: {result.stderr}`, 0)
	end
	for line in result.stdout:gmatch("[^\r\n]+") do
		local mode, path = line:match("^(%d+)%s+[%da-fA-F]+%s+%d+\t(.+)$")
		if not mode then
			error(`invalid tracked component entry: {line}`, 0)
		end
		if mode == "120000" or mode == "160000" then
			error(`{path}: symlinks and gitlinks are not allowed in ci/components`, 0)
		end
	end
end

-- Components are package directories that export a class and static Contract
-- field. Their identities come from their owning directories.
function Discovery.Discover(self: Discovery): { Contract.Contract }
	if not Fs.isDir("ci/components") then
		error("missing ci/components extension point", 0)
	end
	self:RejectLinkedEntries()

	local components: { Contract.Contract } = {}
	local identities: { [string]: string } = {}
	for _, path in Glob.Find("ci/components/*") do
		local name = path:match("([^/]+)$")
		if not name then
			error(`invalid component path: {path}`, 0)
		end
		if name == ".gitkeep" then
			continue
		end

		local metadata = Fs.metadata(path)
		if metadata.kind ~= "dir" then
			error(`{path}: CI components must be package directories`, 0)
		end

		local identity = name
		local entry = `{path}/init.luau`
		if not Fs.isFile(entry) or Fs.metadata(entry).kind == "symlink" then
			error(`{path}: component directory requires a regular init.luau`, 0)
		end
		if not identity:match("^[%w_-]+$") then
			error(`{path}: invalid component directory name`, 0)
		end

		local folded = identity:lower()
		if identities[folded] then
			error(`{path}: ambiguous component identity with {identities[folded]}`, 0)
		end
		identities[folded] = path

		local definition = require(`../components/{identity}`)
		if type(definition) ~= "table" or type(definition.new) ~= "function" then
			error(`{entry}: component module must expose Component.new`, 0)
		end
		local source = definition.Contract
		table.insert(components, Contract.new(identity, entry, source))
	end
	return components
end

return Discovery
