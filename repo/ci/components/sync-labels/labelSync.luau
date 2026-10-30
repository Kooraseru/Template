-- repo/ci/components/sync-labels/labelSync.luau
--!strict

local Publication = require("@ci/github/publication")
local LabelCatalog = require("./labelCatalog")

local LabelSync = {}

function LabelSync.Sync(
	repository: string,
	labels: { LabelCatalog.Label },
	request: typeof(Publication.Request)
): boolean
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
	return changed
end

return LabelSync
