-- .github/ci/integrations/github/resources/milestones/milestoneCatalog.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local Glob = require("@ci/bootstrap/discovery/glob")
local Publication = require("@ci/integrations/github/publication")

local CONFIG_PATH = ".github/work/milestones/records"

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
	local result: { Milestone } = {}
	local versions: { [string]: boolean } = {}
	for _, path in Glob.Find(`{CONFIG_PATH}/*.json`) do
		if not Fs.exists(path) or Fs.type(path) ~= "file" then
			continue
		end
		local entry = Publication.Record(Json.decode(Fs.readFileToString(path)))
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
			error(
				`{CONFIG_PATH}: planned milestone {version} description must be a string of at most 1024 characters`,
				0
			)
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
