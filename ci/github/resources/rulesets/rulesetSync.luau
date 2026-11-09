-- ci/github/resources/rulesets/rulesetSync.luau
--!strict

local Net = require("@lute/net/client")
local Json = require("@formats/json")
local Publication = require("@ci/github/publication")
local RulesetCatalog = require("@ci/github/resources/rulesets/rulesetCatalog")

local RulesetSync = {}
export type Receipt = { identity: string, id: number }

-- Report only the API's validation fields, not the complete request or authorization headers.
local function diagnostic(body: string): string
	local ok, decoded = pcall(Json.decode, body)
	if not ok or type(decoded) ~= "table" then
		return ""
	end
	local decodedRecord = decoded :: { [string]: unknown }
	local parts: { string } = {}

	local function append(value: unknown): ()
		if type(value) ~= "string" or value == "" then
			return
		end
		local cleaned = value:gsub("[%c]", " "):sub(1, 240)
		table.insert(parts, cleaned)
	end

	append(decodedRecord.message)

	if type(decodedRecord.errors) == "table" then
		for _, entry in decodedRecord.errors do
			if type(entry) == "table" then
				local entryRecord = entry :: { [string]: unknown }
				append(entryRecord.field)
				append(entryRecord.code)
				append(entryRecord.message)
			elseif type(entry) == "string" then
				append(entry)
			end
			if #parts >= 8 then
				break
			end
		end
	end
	return if #parts > 0 then ": " .. table.concat(parts, "; "):sub(1, 900) else ""
end

-- The JSON encoder represents an empty Luau table as {}, even when GitHub requires a JSON array.
local function encodeRequestBody(value: unknown): string
	local encoded = Json.encode(value)
	if type(value) ~= "table" then
		return encoded
	end
	local request = value :: { [string]: unknown }

	local function replaceEmptyArray(field: string): ()
		local original = '"' .. field .. '":{}'
		local replacement = '"' .. field .. '":[]'
		local converted, count = encoded:gsub(original, replacement, 1)
		if count ~= 1 then
			error(`Rulesets API payload is missing expected empty array {field}`, 0)
		end
		encoded = converted
	end

	local bypass = request.bypass_actors
	if type(bypass) == "table" and next(bypass) == nil then
		replaceEmptyArray("bypass_actors")
	end
	local conditions = request.conditions

	if type(conditions) == "table" then
		local conditionRecord = conditions :: { [string]: unknown }
		local refName = conditionRecord.ref_name
		if type(refName) == "table" then
			local refNameRecord = refName :: { [string]: unknown }
			local exclude = refNameRecord.exclude
			if type(exclude) == "table" and next(exclude) == nil then
				replaceEmptyArray("exclude")
			end
		end
	end
	return encoded
end

local function request(token: string, method: string, path: string, body: unknown?): (number, unknown)
	local response = Net.request(`https://api.github.com/{path}`, {
		method = method,
		headers = {
			Authorization = `Bearer {token}`,
			Accept = "application/vnd.github+json",
			["Content-Type"] = "application/json",
			["X-GitHub-Api-Version"] = "2022-11-28",
			["User-Agent"] = "Luau-CI-rulesets",
		},
		body = if body ~= nil then encodeRequestBody(body) else nil,
	})

	if response.status == 401 or response.status == 403 then
		error(
			`Rulesets API rejected Administration: write authorization (HTTP {response.status}){diagnostic(
				response.body
			)}`,
			0
		)
	end

	if response.status < 200 or response.status >= 300 then
		error(`Rulesets API {method} failed (HTTP {response.status}){diagnostic(response.body)}`, 0)
	end
	local result: unknown = if response.body ~= "" then Json.decode(response.body) else {}
	return response.status, result
end

local function matches(actual: unknown, desired: unknown): boolean
	if type(desired) ~= "table" then
		return actual == desired
	end
	if type(actual) ~= "table" then
		return false
	end
	local desiredRecord = desired :: { [string]: unknown }
	local actualRecord = actual :: { [string]: unknown }
	-- GitHub may add server-owned response fields; only compare declared properties.
	for key, value in desiredRecord do
		if not matches(actualRecord[key], value) then
			return false
		end
	end
	return true
end

function RulesetSync.Sync(
	repository: string,
	token: string,
	definitions: { RulesetCatalog.Ruleset }
): ({ Receipt }, boolean)
	local prefix = `repos/{repository}/rulesets`
	local existing: { { [string]: unknown } } = {}
	local page = 1

	while true do
		local _, records = request(token, "GET", `{prefix}?includes_parents=false&per_page=100&page={page}`)
		if type(records) ~= "table" then
			error("Rulesets API returned an invalid collection", 0)
		end
		for _, item in records do
			table.insert(existing, Publication.Record(item))
		end
		if #records < 100 then
			break
		end
		page += 1
	end

	local byName: { [string]: { [string]: unknown } } = {}

	for _, entry in existing do
		local name = Publication.Text(entry.name):lower()
		if byName[name] then
			error(`Ambiguous existing ruleset name {name}`, 0)
		end
		byName[name] = entry
	end

	local receipts: { Receipt } = {}
	local changed = false

	for _, ruleset in definitions do
		local definition = ruleset.definition
		local name = Publication.Text(definition.name)
		local current = byName[name:lower()]
		local id: number

		if current then
			id = current.id :: number
			if type(id) ~= "number" then
				error(`Ruleset {name} has an invalid remote ID`, 0)
			end
			local _, detail = request(token, "GET", `{prefix}/{id}`)
			if not matches(detail, definition) then
				print(`::notice::Applying ruleset update {ruleset.identity} (ID {id})`)
				request(token, "PUT", `{prefix}/{id}`, definition)
				changed = true
				print(`Updated managed ruleset {ruleset.identity}`)
			end
		else
			print(`::notice::Creating managed ruleset {ruleset.identity}`)
			local _, created = request(token, "POST", prefix, definition)
			local data = Publication.Record(created)
			id = data.id :: number
			if type(id) ~= "number" then
				error(`Rulesets API did not return an ID for {name}`, 0)
			end
			changed = true
			print(`Created managed ruleset {ruleset.identity}`)
		end

		table.insert(receipts, { identity = ruleset.identity, id = id })
	end
	-- Never delete a remote ruleset that cannot be tied to one of our flat TOML files.
	return receipts, changed
end

return RulesetSync
