-- .github/ci/integrations/github/resources/milestones/milestoneSync.luau
--!strict

local Net = require("@lute/net/client")
local Json = require("@formats/json")
local Publication = require("@ci/integrations/github/publication")
local Catalog = require("@ci/integrations/github/resources/milestones/milestoneCatalog")

local MilestoneSync = {}
export type Receipt = { version: string, id: number, state: string }

local function request(token: string, method: string, path: string, body: unknown?): (number, unknown)
	local response = Net.request(`https://api.github.com/{path}`, {
		method = method,
		headers = {
			Authorization = `Bearer {token}`,
			Accept = "application/vnd.github+json",
			["Content-Type"] = "application/json",
			["X-GitHub-Api-Version"] = "2022-11-28",
			["User-Agent"] = "Luau-CI-milestones",
		},
		body = if body ~= nil then Json.encode(body) else nil,
	})
	if response.status == 401 or response.status == 403 then
		error(`Milestones API rejected Issues: write authorization (HTTP {response.status})`, 0)
	end
	if response.status < 200 or response.status >= 300 then
		error(`Milestones API {method} failed (HTTP {response.status})`, 0)
	end
	return response.status, if response.body ~= "" then Json.decode(response.body) else {}
end

local function body(milestone: Catalog.Milestone): { [string]: unknown }
	local result: { [string]: unknown } = {
		title = milestone.version,
		state = if milestone.status == "released" then "closed" else "open",
	}
	if milestone.description ~= nil then
		result.description = milestone.description
	end
	if milestone.due_on ~= nil then
		result.due_on = milestone.due_on
	end
	return result
end

function MilestoneSync.Sync(
	repository: string,
	token: string,
	milestones: { Catalog.Milestone }
): ({ Receipt }, boolean)
	local prefix = `repos/{repository}/milestones`
	local existing: { { [string]: unknown } } = {}
	local page = 1
	while true do
		local _, records = request(token, "GET", `{prefix}?state=all&per_page=100&page={page}`)
		if type(records) ~= "table" then
			error("Milestones API returned an invalid collection", 0)
		end
		for _, item in records do
			table.insert(existing, Publication.Record(item))
		end
		if #records < 100 then
			break
		end
		page += 1
	end
	local byTitle: { [string]: { [string]: unknown } } = {}
	for _, entry in existing do
		local title = Publication.Text(entry.title)
		if byTitle[title] then
			error(`Ambiguous existing milestone title {title}`, 0)
		end
		byTitle[title] = entry
	end
	local receipts: { Receipt } = {}
	local changed = false
	for _, milestone in milestones do
		local desired = body(milestone)
		local current = byTitle[milestone.version]
		local id: number
		local state = desired.state :: string
		if current then
			id = current.number :: number
			if type(id) ~= "number" then
				error(`Milestone {milestone.version} has an invalid remote ID`, 0)
			end
			local unchanged = current.title == desired.title and current.state == desired.state
			if desired.description ~= nil and current.description ~= desired.description then
				unchanged = false
			end
			if desired.due_on ~= nil and current.due_on ~= desired.due_on then
				unchanged = false
			end
			if not unchanged then
				request(token, "PATCH", `{prefix}/{id}`, desired)
				changed = true
				print(`Updated milestone {milestone.version} ({state})`)
			end
		else
			if milestone.status == "released" then
				print(`Released milestone {milestone.version} was not found; leaving GitHub unchanged`)
				continue
			end
			local _, created = request(token, "POST", prefix, desired)
			local data = Publication.Record(created)
			id = data.number :: number
			if type(id) ~= "number" then
				error(`Milestones API did not return an ID for {milestone.version}`, 0)
			end
			changed = true
			print(`Created milestone {milestone.version} ({state})`)
		end
		table.insert(receipts, { version = milestone.version, id = id, state = state })
	end
	-- Unlisted remote milestones are repository history and are never deleted or modified.
	return receipts, changed
end

return MilestoneSync
