-- repo/ci/components/publish-releases/init.luau
--!strict

local Fs = require("@lune/fs")
local Publication = require("@ci/github/publication")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	local repository = Publication.Begin("RELEASES")
	if not repository then
		return
	end
	for _, value in Publication.ReadIndex("build/repo/releases/index.json", "releases") do
		local entry = Publication.Record(value)
		local tag = Publication.Text(entry.tag)
		local commit = Publication.Text(entry.commit)
		local status = Publication.Request("GET", `repos/{repository}/releases/tags/{Publication.Encode(tag)}`)
		if status == 200 then
			print(`Release {tag} already exists; preserving published release`)
			continue
		elseif status ~= 404 then
			Publication.RequireSuccess(status, `Look up release {tag}`)
		end
		local body = ""
		if entry.notes then
			local notes = Publication.Text(entry.notes)
			if notes:find("..", 1, true) or notes:sub(1, 1) == "/" or notes:find("\\", 1, true) then
				error("Unsafe staged release notes path", 0)
			end
			body = Fs.readFile(`build/repo/releases/{notes}`)
		end
		if entry.previousTag then
			local previousTag = Publication.Text(entry.previousTag)
			local notesStatus, generated = Publication.Request("POST", `repos/{repository}/releases/generate-notes`, {
				tag_name = tag,
				target_commitish = commit,
				previous_tag_name = previousTag,
			})
			Publication.RequireSuccess(notesStatus, `Generate release notes for {tag} from {previousTag}`)
			body ..= "\n\n" .. Publication.Text(generated.body)
		end
		local created = Publication.Request("POST", `repos/{repository}/releases`, {
			tag_name = tag,
			target_commitish = commit,
			name = tag,
			body = body,
			prerelease = entry.prerelease == true,
		})
		Publication.RequireSuccess(created, `Publish release {tag}`)
		print(`Published release https://github.com/{repository}/releases/tag/{tag}`)
	end
end

return Component
