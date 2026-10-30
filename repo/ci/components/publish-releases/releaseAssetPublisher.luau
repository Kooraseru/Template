-- repo/ci/components/publish-releases/releaseAssetPublisher.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Publication = require("@ci/github/publication")

local ReleaseAssetPublisher = {}
export type Asset = { name: string, bytes: string, digest: string }
export type Io = {
	request: typeof(Publication.Request),
	list: typeof(Publication.List),
	upload: typeof(Publication.Upload),
}

function ReleaseAssetPublisher.Read(value: unknown): { Asset }
	local assets: { Asset } = {}
	if value == nil then
		return assets
	end
	if type(value) ~= "table" then
		error("Staged release assets must be an array", 0)
	end
	local names: { [string]: boolean } = {}
	for _, item in value do
		local record = Publication.Record(item)
		local name = Publication.Text(record.name)
		local path = Publication.Text(record.path)
		local digest = Publication.Text(record.digest)
		if not name:match("^[%w][%w_.%-]*$") or #name > 180 or names[name:lower()] then
			error("Duplicate or unsafe release asset name", 0)
		end
		names[name:lower()] = true
		if not path:match("^build/repo/releases/[%w_./%-]+$") or path:find("..", 1, true) then
			error("Release asset must be a staged file under build/repo/releases/", 0)
		end
		if Fs.metadata(path).kind ~= "file" then
			error(`Missing staged release asset: {path}`, 0)
		end
		local bytes = Fs.readFile(path)
		if digest ~= "sha256:" .. Serde.hash("sha256", bytes) then
			error(`Release asset checksum mismatch: {name}`, 0)
		end
		table.insert(assets, { name = name, bytes = bytes, digest = digest })
	end
	return assets
end

local function assetId(record: { [string]: unknown }): number
	local id = record.id
	if type(id) ~= "number" then
		error("GitHub returned an invalid asset ID", 0)
	end
	return id
end

local function verify(record: { [string]: unknown }, asset: Asset): ()
	if record.digest ~= asset.digest or record.state ~= "uploaded" then
		error(`GitHub did not confirm the uploaded checksum for {asset.name}; existing assets have not been deleted`, 0)
	end
end

function ReleaseAssetPublisher.Sync(repository: string, releaseId: number, assets: { Asset }, io: Io): ()
	if #assets == 0 then
		return
	end
	local existing: { [string]: { [string]: unknown } } = {}
	local page = 1
	while true do
		local items = io.list(`repos/{repository}/releases/{releaseId}/assets?per_page=100&page={page}`)
		for _, item in items do
			local record = Publication.Record(item)
			existing[Publication.Text(record.name)] = record
		end
		if #items < 100 then
			break
		end
		page += 1
	end
	for _, asset in assets do
		local previous = existing[asset.name]
		if previous and previous.digest == asset.digest and previous.state == "uploaded" then
			print(`Verified existing release asset {asset.name}`)
			continue
		end
		local temporaryName = asset.name .. ".ci-" .. asset.digest:sub(8)
		local pending = existing[temporaryName]
		if previous or pending then
			-- Keep the old download available until its replacement is uploaded and verified.
			local uploaded = pending or io.upload(repository, releaseId, temporaryName, asset.bytes)
			verify(uploaded, asset)
			local uploadedId = assetId(uploaded)
			if previous then
				local deleted = io.request("DELETE", `repos/{repository}/releases/assets/{assetId(previous)}`, nil)
				Publication.RequireSuccess(
					deleted,
					`Replace release asset {asset.name}; verified replacement remains as {temporaryName}`
				)
			end
			local renamed =
				io.request("PATCH", `repos/{repository}/releases/assets/{uploadedId}`, { name = asset.name })
			Publication.RequireSuccess(
				renamed,
				`Name replacement release asset {asset.name}; uploaded file remains as {temporaryName}`
			)
		else
			local uploaded = io.upload(repository, releaseId, asset.name, asset.bytes)
			verify(uploaded, asset)
		end
		print(`Published release asset {asset.name} ({asset.digest})`)
	end
end

return ReleaseAssetPublisher
