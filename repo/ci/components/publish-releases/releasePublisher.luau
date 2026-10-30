-- repo/ci/components/publish-releases/releasePublisher.luau
--!strict

local Fs = require("@lune/fs")
local Publication = require("@ci/github/publication")
local ConflictPolicy = require("@ci/github/conflictPolicy")
local ReleaseAssetPublisher = require("./releaseAssetPublisher")

type Request = (
	method: "GET" | "POST" | "PATCH" | "PUT" | "DELETE",
	path: string,
	body: unknown?
) -> (number, { [string]: unknown })

local ReleasePublisher = {}

function ReleasePublisher.Publish(
	repository: string,
	entry: { [string]: unknown },
	policy: ConflictPolicy.Policy,
	request: Request,
	assetIo: ReleaseAssetPublisher.Io?
): boolean
	local tag = Publication.Text(entry.tag)
	local commit = Publication.Text(entry.commit)
	local encodedTag = Publication.Encode(tag)
	local releaseStatus, existing = request("GET", `repos/{repository}/releases/tags/{encodedTag}`)
	if releaseStatus ~= 404 then
		Publication.RequireSuccess(releaseStatus, `Look up release {tag}`)
	end
	local tagStatus, reference = request("GET", `repos/{repository}/git/ref/tags/{encodedTag}`)
	if tagStatus ~= 404 then
		Publication.RequireSuccess(tagStatus, `Look up tag {tag}`)
	end
	local decision = ConflictPolicy.Resolve(
		policy,
		releaseStatus == 200 or tagStatus == 200,
		existing.immutable ~= true,
		`Release/tag {tag}`
	)
	if decision == "skip" then
		print(`Release/tag {tag} already exists; on_existing = skip`)
		return false
	end
	local releaseId = existing.id
	if releaseStatus == 200 and type(releaseId) ~= "number" then
		error("Invalid GitHub release ID", 0)
	end
	local assets = ReleaseAssetPublisher.Read(entry.assets)
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
		local notesStatus, generated = request("POST", `repos/{repository}/releases/generate-notes`, {
			tag_name = tag,
			target_commitish = commit,
			previous_tag_name = previousTag,
		})
		Publication.RequireSuccess(notesStatus, `Generate release notes for {tag} from {previousTag}`)
		body ..= "\n\n" .. Publication.Text(generated.body)
	end
	if tagStatus == 200 then
		local object = Publication.Record(reference.object)
		local depth = 0
		while object.type == "tag" do
			depth += 1
			if depth > 10 then
				error(`Tag {tag}: annotation chain is too deep`, 0)
			end
			local objectStatus, annotation =
				request("GET", `repos/{repository}/git/tags/{Publication.Text(object.sha)}`)
			Publication.RequireSuccess(objectStatus, `Resolve annotated tag {tag}`)
			object = Publication.Record(annotation.object)
		end
		if object.type ~= "commit" then
			error(`Tag {tag} does not identify a commit`, 0)
		end
		if object.sha ~= commit then
			local updated =
				request("PATCH", `repos/{repository}/git/refs/tags/{encodedTag}`, { sha = commit, force = true })
			Publication.RequireSuccess(updated, `Replace tag {tag}; tag protection and immutability remain enforced`)
		end
	end
	local payload = {
		tag_name = tag,
		target_commitish = commit,
		name = tag,
		body = body,
		prerelease = entry.prerelease == true,
		draft = #assets > 0 and (releaseStatus ~= 200 or existing.draft == true),
	}
	local status: number
	local published: { [string]: unknown }
	if releaseStatus == 200 and type(releaseId) == "number" then
		status, published = request("PATCH", `repos/{repository}/releases/{releaseId}`, payload)
	else
		status, published = request("POST", `repos/{repository}/releases`, payload)
	end
	Publication.RequireSuccess(status, `Publish release {tag}; a tag update may already have succeeded`)
	if #assets > 0 then
		local id = if releaseStatus == 200 then releaseId else published.id
		if type(id) ~= "number" then
			error("GitHub returned no release ID for asset upload", 0)
		end
		local io = assetIo or { request = request, list = Publication.List, upload = Publication.Upload }
		ReleaseAssetPublisher.Sync(repository, id, assets, io)
		if payload.draft then
			local finalized = request("PATCH", `repos/{repository}/releases/{id}`, { draft = false })
			Publication.RequireSuccess(finalized, `Publish completed draft release {tag}`)
		end
	end
	print(`Published release https://github.com/{repository}/releases/tag/{tag} (on_existing = {policy})`)
	return true
end

return ReleasePublisher
