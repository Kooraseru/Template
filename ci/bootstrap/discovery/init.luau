-- ci/bootstrap/discovery/init.luau
--!strict

local Fs = require("@std/fs")
local Process = require("@lute/process")
local Toml = require("@formats/toml")

local Contract = require("@ci/bootstrap/contracts/contract")
local Glob = require("@ci/bootstrap/discovery/glob")

local Discovery = {}
Discovery.__index = Discovery

export type Discovery = setmetatable<{}, typeof(Discovery)>

function Discovery.new(): Discovery
	local fields = {}
	return setmetatable(fields, Discovery)
end

--[[
Filesystem metadata may follow symlinks on supported platforms. The
checked-out Git tree supplies the authoritative type of tracked entries;
reject links before walking a discovered extension point.
]]
function Discovery.RejectLinkedEntries(self: Discovery): ()
	local result = Process.run({ "git", "ls-files", "--stage", "--", Contract.ComponentRoot })
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

--[[
Grouping folders are traversed recursively. A component starts at a manifest or
entry point; its private implementation directories are not extension points.
]]
function Discovery.Discover(self: Discovery): { Contract.Contract }
	if not Fs.exists(Contract.ComponentRoot) or Fs.metadata(Contract.ComponentRoot).type ~= "dir" then
		error("missing ci/components extension point", 0)
	end
	self:RejectLinkedEntries()
	local settingsPath = ".github/config/ci/settings.toml"
	local decoded = Toml.decode(Fs.readFileToString(settingsPath))
	local decodedSettings = if type(decoded) == "table" then (decoded :: { [string]: unknown }).components else nil
	if type(decodedSettings) ~= "table" then
		error(`{settingsPath}: expected boolean default and an [enabled] table`, 0)
	end
	local settings = decodedSettings :: { [string]: unknown }
	if type(settings.default) ~= "boolean" or type(settings.enabled) ~= "table" then
		error(`{settingsPath}: expected boolean default and an [enabled] table`, 0)
	end

	for key in settings do
		if key ~= "default" and key ~= "enabled" then
			error(`{settingsPath}: unknown setting {tostring(key)}`, 0)
		end
	end

	local overrides: { [string]: boolean } = {}
	local enabledOverrides = settings.enabled :: { [string]: unknown }

	for identity, enabled in enabledOverrides do
		if type(identity) ~= "string" or not Contract.ValidIdentity(identity) or type(enabled) ~= "boolean" then
			error(`{settingsPath}: enabled entries require valid component identities and booleans`, 0)
		end
		overrides[identity] = enabled
	end

	local components: { Contract.Contract } = {}
	local identities: { [string]: string } = {}
	local packages: { string } = {}

	for _, path in Glob.Find(Contract.ComponentRoot .. "/**") do
		if path == Contract.ComponentRoot then
			continue
		end
		local private = false

		for _, package in packages do
			if path:sub(1, #package + 1) == package .. "/" then
				private = true
				break
			end
		end

		if private then
			continue
		end
		local name = path:match("([^/]+)$")
		local metadata = Fs.metadata(path)
		if metadata.type == "file" and (name == ".gitkeep" or name == "README.md") then
			continue
		end
		if metadata.type ~= "dir" then
			error(`{path}: grouping folders may contain component folders, README.md, or .gitkeep`, 0)
		end
		local identity = path:sub((#Contract.ComponentRoot + 1) + 1)
		if not Contract.ValidIdentity(identity) then
			error(`{path}: invalid grouping or component identity`, 0)
		end
		local folded = identity:lower()
		if identities[folded] then
			error(`{path}: ambiguous identity with {identities[folded]}`, 0)
		end
		identities[folded] = path
		local entry = `{path}/init.luau`
		local contractFile = `{path}/component.toml`
		if not Fs.exists(entry) and not Fs.exists(contractFile) then
			continue
		end
		local hasModule = Fs.exists(entry)
		if hasModule and Fs.metadata(entry).type ~= "file" then
			error(`{path}: init.luau must be a regular file`, 0)
		end
		if not Fs.exists(contractFile) or Fs.metadata(contractFile).type ~= "file" then
			error(`{path}: component directory requires a regular component.toml`, 0)
		end
		table.insert(packages, path)

		local loaded, source = xpcall(function(): unknown
			return Toml.decode(Fs.readFileToString(contractFile))
		end, tostring)
		if not loaded then
			error(`{contractFile}: unable to parse component manifest: {source}`, 0)
		end
		local component = Contract.new(identity, if hasModule then entry else contractFile, contractFile, source)
		if (component.command ~= nil) == hasModule then
			error(`{contractFile}: component requires exactly one implementation: init.luau or command`, 0)
		end
		local enabled = overrides[identity]
		component.enabled = if enabled ~= nil then enabled else settings.default
		overrides[identity] = nil
		table.insert(components, component)
	end

	for identity in overrides do
		error(`{settingsPath}: no discovered component matches {identity}`, 0)
	end
	return components
end

return Discovery
