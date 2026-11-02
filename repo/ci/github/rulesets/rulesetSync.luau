-- repo/ci/github/rulesets/rulesetSync.luau
--!strict

local Net = require("@lune/net")
local Serde = require("@lune/serde")
local Publication = require("@ci/github/publication")
local RulesetCatalog = require("@ci/github/rulesets/rulesetCatalog")

local RulesetSync = {}
export type Receipt = { identity: string, id: number }

local function request(
	token: string,
	method: Net.HttpMethod,
	path: string,
	body: unknown?
): (number, unknown)
	local response = Net.request({
		url = `https://api.github.com/{path}`,
		method = method,
		headers = {
			Authorization = `Bearer {token}`,
			Accept = "application/vnd.github+json",
			["Content-Type"] = "application/json",
			["X-GitHub-Api-Version"] = "2022-11-28",
			["User-Agent"] = "Luau-CI-rulesets",
		},
		body = if body ~= nil then Serde.encode("json", body) else nil,
	})
	if response.statusCode == 401 or response.statusCode == 403 then
		error(`Rulesets API rejected Administration: write authorization (HTTP {response.statusCode})`, 0)
	end
	if response.statusCode < 200 or response.statusCode >= 300 then
		error(`Rulesets API {method} failed (HTTP {response.statusCode})`, 0)
	end
	local result: unknown = if response.body ~= "" then Serde.decode("json", response.body) else {}
	return response.statusCode, result
end

local function matches(actual: unknown, desired: unknown): boolean
	if type(desired) ~= "table" then
		return actual == desired
	end
	if type(actual) ~= "table" then
		return false
	end
	-- GitHub may add server-owned response fields; only compare declared properties.
	if #actual ~= #desired then
		return false
	end
	for key, value in desired do
		if not matches(actual[key], value) then
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
				request(token, "PUT", `{prefix}/{id}`, definition)
				changed = true
				print(`Updated managed ruleset {ruleset.identity}`)
			end
		else
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
