-- repo/ci/components/sync-labels/labelSync.luau
--!strict

local Publication = require("@ci/github/publication")
local LabelCatalog = require("./labelCatalog")

local LabelSync = {}

function LabelSync.Sync(
	repository: string,
	labels: { LabelCatalog.Label },
	request: typeof(Publication.Request),
	list: typeof(Publication.List)?
): boolean
	local read = list or Publication.List
	local remote: { string } = {}
	local page = 1
	while true do
		local items = read(`repos/{repository}/labels?per_page=100&page={page}`)
		for _, value in items do
			table.insert(remote, Publication.Text(Publication.Record(value).name))
		end
		if #items < 100 then
			break
		end
		page += 1
	end
	local declared: { [string]: boolean } = {}
	for _, label in labels do
		declared[label.name:lower()] = true
	end
	local changed = false
	for _, label in labels do
		local path = `repos/{repository}/labels/{Publication.Encode(label.name)}`
		local status, current = request("GET", path, nil)
		if status == 404 then
			local created = request("POST", `repos/{repository}/labels`, label)
			Publication.RequireSuccess(created, `Create label {label.name}; issues write permission is required`)
			print(`Created label {label.name}`)
			changed = true
		else
			Publication.RequireSuccess(status, `Read label {label.name}`)
			if current.archived_at ~= nil then
				error(`Configured label {label.name} is archived; unarchive it before using it in templates`, 0)
			end
			if
				current.name == label.name
				and current.color == label.color
				and current.description == label.description
			then
				print(`Label {label.name} already matches its definition`)
				continue
			end
			local updated =
				request("PATCH", path, { new_name = label.name, color = label.color, description = label.description })
			Publication.RequireSuccess(updated, `Update label {label.name}; issues write permission is required`)
			print(`Updated label {label.name}`)
			changed = true
		end
	end
	-- Upsert the complete validated catalog before pruning any remote labels.
	for _, name in remote do
		if declared[name:lower()] then
			continue
		end
		local deleted = request("DELETE", `repos/{repository}/labels/{Publication.Encode(name)}`, nil)
		if deleted ~= 404 then
			Publication.RequireSuccess(deleted, `Remove undeclared label {name}`)
		end
		print(`Removed undeclared label {name}`)
		changed = true
	end
	return changed
end

return LabelSync
