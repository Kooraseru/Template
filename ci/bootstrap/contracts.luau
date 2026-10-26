-- ci/bootstrap/contracts.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")

local Component = require("./component")
local Glob = require("./glob")

local Contracts = {}

-- A component declares its contract in a leading TOML comment. Reading this
-- header must never require or execute code discovered under ci/components.
local function readContract(entry: string): unknown
	local source = Fs.readFile(entry):gsub("\r\n", "\n")
	local header = `-- {entry}\n--!strict\n--[[ci-contract\n`
	if source:sub(1, #header) ~= header then
		error(`{entry}: expected path label, --!strict, and leading ci-contract comment`, 0)
	end

	local marker = "\nend-ci-contract]]"
	local finish = source:find(marker, #header + 1, true)
	if not finish then
		error(`{entry}: missing end-ci-contract marker`, 0)
	end

	local ok, decoded = pcall(Serde.decode, "toml", source:sub(#header + 1, finish - 1))
	if not ok then
		error(`{entry}: invalid contract TOML: {decoded}`, 0)
	end
	return decoded
end

-- Lune's filesystem metadata follows symlinks on supported releases. The
-- checked-out Git tree supplies the authoritative type of tracked entries;
-- reject links before walking a discovered extension point.
local function rejectLinkedEntries()
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

-- File and directory heads are equivalent child shapes. Candidate identities
-- are derived from the owning directory, not repeated in a CI inventory.
function Contracts.Discover()
	if not Fs.isDir("ci/components") then
		error("missing ci/components extension point", 0)
	end
	rejectLinkedEntries()

	local components = {}
	local identities = {}
	for _, path in Glob.Find("ci/components/*") do
		local name = path:match("([^/]+)$")
		if name == ".gitkeep" then
			continue
		end

		local metadata = Fs.metadata(path)
		local identity: string
		local entry: string
		if metadata.kind == "file" and name:sub(-5) == ".luau" then
			identity = name:sub(1, -6)
			entry = path
		elseif metadata.kind == "dir" then
			identity = name
			entry = `{path}/init.luau`
			if not Fs.isFile(entry) or Fs.metadata(entry).kind == "symlink" then
				error(`{path}: component directory requires a regular init.luau`, 0)
			end
		else
			error(`{path}: unexpected direct child under ci/components`, 0)
		end

		local folded = identity:lower()
		if identities[folded] then
			error(`{path}: ambiguous component identity with {identities[folded]}`, 0)
		end
		identities[folded] = path
		table.insert(components, Component.new(identity, entry, readContract(entry)))
	end
	return components
end

return Contracts
