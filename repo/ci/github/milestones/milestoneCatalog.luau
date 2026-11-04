--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Publication = require("@ci/github/publication")

const CONFIG_PATH = "repo/content/releases/releases.json"

local MilestoneCatalog = {}

export type Milestone = {
	version: string,
	status: "planned" | "released",
	due_on: string?,
	description: string?,
}

local function validDueDate(value: string): boolean
	return value:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil
end

function MilestoneCatalog.Read(): { Milestone }
	local root = Publication.Record(Serde.decode("json", Fs.readFile(CONFIG_PATH)))
	local release = Publication.Record(root.release)
	local planned = release.planned
	if planned == nil then
		return {}
	end
	if type(planned) ~= "table" then
		error(`{CONFIG_PATH}: release.planned must be an array of objects`, 0)
	end
	local result: { Milestone } = {}
	local versions: { [string]: boolean } = {}
	for index, value in planned do
		if type(index) ~= "number" or type(value) ~= "table" then
			error(`{CONFIG_PATH}: release.planned entries must be objects`, 0)
		end
		local entry = Publication.Record(value)
		for field in entry do
			if field ~= "version" and field ~= "status" and field ~= "due_on" and field ~= "description" then
				error(`{CONFIG_PATH}: unsupported planned milestone field {tostring(field)}`, 0)
			end
		end
		local version = Publication.Text(entry.version)
		if #version > 256 or version:find("[%c]") then
			error(`{CONFIG_PATH}: planned milestone version must be at most 256 printable characters`, 0)
		end
		if versions[version] then
			error(`{CONFIG_PATH}: duplicate planned milestone version {version}`, 0)
		end
		local status = entry.status
		if status ~= "planned" and status ~= "released" then
			error(`{CONFIG_PATH}: planned milestone {version} status must be planned or released`, 0)
		end
		local normalizedStatus = status :: "planned" | "released"
		local dueOn = entry.due_on
		if dueOn ~= nil and (type(dueOn) ~= "string" or not validDueDate(dueOn)) then
			error(`{CONFIG_PATH}: planned milestone {version} due_on must be an RFC 3339 UTC timestamp`, 0)
		end
		local description = entry.description
		if description ~= nil and (type(description) ~= "string" or #description > 1024) then
			error(`{CONFIG_PATH}: planned milestone {version} description must be a string of at most 1024 characters`, 0)
		end
		versions[version] = true
		table.insert(result, {
			version = version,
			status = normalizedStatus,
			due_on = dueOn,
			description = description,
		})
	end
	return result
end

return MilestoneCatalog
