-- ci/publication/releases/publish.luau
--!strict

local Publish = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Process = require("@lune/process")
local C = require("../../libraries/bootstrap/canonical")
local D = require("../../libraries/bootstrap/documents")
local Json = require("../../libraries/bootstrap/json")
local Shape = require("../../libraries/registry/shape")
local Base64 = require("../../libraries/bootstrap/base64")
local Authorization = require("../../integration/publication")
local Hosted = require("../../security/receipts/hosted")
local Versions = require("./versions")
local Render = require("./render")
local Client = require("./client")
local Protection = require("./protection")
local Distributions = require("./distributions")

--# Helpers

local function commit(api: Client.API, ref: C.Value?): C.Value?
	if not ref then
		return nil
	end
	local object = D.Required(ref, "object")
	for _ = 1, 16 do
		if D.Get(object, "type") ~= "tag" then
			break
		end
		object = D.Required(assert(api.Request("/git/tags/" .. D.Text(object, "sha"))), "object")
	end
	assert(D.Get(object, "type") == nil or D.Get(object, "type") == "commit", "version tag does not resolve to commit")
	return D.Get(object, "sha")
end

local function encode(value: string): string
	return (value:gsub("[^%w%-_%.~]", function(character)
		return string.format("%%%02X", character:byte())
	end))
end

--# Functions

function Publish.Version(api: Client.API, metadata: C.Value, root: string, assertFresh: () -> ())
	local identity = Versions.Parse(D.Text(metadata, "version"))
	assert(D.Get(metadata, "schema") == nil, "release contains unsupported schema field")
	local sha = D.Text(metadata, "source_sha")
	assert(
		D.Get(metadata, "prerelease") == identity.prerelease
			and D.Get(metadata, "type") == identity.type
			and #sha == 40
			and sha:match("^[a-f0-9]+$"),
		"invalid version metadata"
	)
	local version = identity.version
	local bytes = Fs.readFile(root .. "/release.json")
	assert(D.Equal(C.Decode(bytes), metadata), "release manifest changed")
	local body = Fs.readFile(root .. "/notes.md")
		.. "\n<!-- semver-release:"
		.. version
		.. ":"
		.. Serde.hash("sha256", bytes)
		.. " -->\n"
	local payloads = D.Items(metadata, "assets")
	local contentTypes =
		D.Required(D.Required(D.Read("ci/publication/releases/ruleset.json"), "rules"), "asset_content_types")
	local function contentType(asset: C.Value): string
		local extension = D.Text(asset, "path"):match("(%.[^./]+)$")
		return if extension and D.Get(contentTypes, extension)
			then D.Text(contentTypes, extension)
			else "application/octet-stream"
	end
	local names: { [string]: boolean } = {}
	for _, asset in payloads do
		local path = Shape.Relative(D.Text(asset, "path"))
		local name = D.Text(asset, "name")
		assert(not names[name], "duplicate public asset names")
		names[name] = true
		local contents = Fs.readFile(root .. "/" .. path)
		assert(
			Render.Executable(contents)
				and name == version .. "-" .. assert(path:match("([^/]+)$"))
				and D.Get(asset, "sha256") == Serde.hash("sha256", contents),
			"release asset changed after assembly"
		)
	end
	local function assetMatches(actual: C.Value?, expected: C.Value): boolean
		if
			not actual
			or D.Get(actual, "size") ~= #Fs.readFile(root .. "/" .. D.Text(expected, "path"))
			or D.Get(actual, "content_type") ~= contentType(expected)
		then
			return false
		end
		if Json.Truthy(D.Get(actual, "digest")) then
			return D.Get(actual, "digest") == "sha256:" .. D.Text(expected, "sha256")
		end
		local data = assert(api.Bytes("/releases/assets/" .. D.Number(actual, "id"), { Binary = true }))
		return Serde.hash("sha256", data) == D.Text(expected, "sha256")
	end
	local function checkAssets(assets: { C.Value }, complete: boolean): boolean
		if complete and #assets ~= #payloads then
			return false
		end
		local seen: { [string]: boolean } = {}
		for _, actual in assets do
			local name = D.Text(actual, "name")
			if seen[name] then
				return false
			end
			seen[name] = true
			local expected: C.Value? = nil
			for _, asset in payloads do
				if D.Get(asset, "name") == name then
					expected = asset
					break
				end
			end
			if not expected or not assetMatches(actual, expected) then
				return false
			end
		end
		return true
	end
	local function matches(release: C.Value): boolean
		return D.Get(release, "tag_name") == version
			and D.Get(release, "name") == version
			and D.Get(release, "prerelease") == identity.prerelease
			and D.Get(release, "body") == body
	end
	local release = api.Request("/releases/tags/" .. version, { Missing = true })
	local originalRef = api.Request("/git/ref/tags/" .. version, { Missing = true })
	local assets = if release then api.Pages("/releases/" .. D.Number(release, "id") .. "/assets") else {}
	if
		release
		and D.Get(release, "draft") == false
		and matches(release)
		and commit(api, originalRef) == sha
		and checkAssets(assets, true)
	then
		assertFresh()
		if not Json.Truthy(D.Get(release, "discussion_url")) then
			api.JSON(
				"PATCH",
				"/releases/" .. D.Number(release, "id"),
				C.Object({ discussion_category_name = "Announcements" })
			)
		end
		return
	end
	local created = false
	local ok, failure = pcall(function()
		assertFresh()
		if not release then
			release = api.JSON(
				"POST",
				"/releases",
				C.Object({
					tag_name = version,
					target_commitish = sha,
					name = version,
					body = body,
					draft = true,
					prerelease = identity.prerelease,
				})
			)
			created = true
		end
		local current = assert(release)
		local route = "/releases/" .. D.Number(current, "id")
		if not created then
			api.JSON("PATCH", route, C.Object({ name = version, body = body, prerelease = identity.prerelease }))
			for _, actual in assets do
				local expected: C.Value? = nil
				for _, asset in payloads do
					if D.Equal(D.Get(asset, "name"), D.Get(actual, "name")) then
						expected = asset
						break
					end
				end
				if not expected or not assetMatches(actual, expected) then
					api.Request("/releases/assets/" .. D.Number(actual, "id"), { Method = "DELETE" })
				end
			end
			assets = api.Pages(route .. "/assets")
		end
		for _, asset in payloads do
			local exists = false
			for _, actual in assets do
				exists = exists or D.Equal(D.Get(asset, "name"), D.Get(actual, "name"))
			end
			if exists then
				continue
			end
			local upload = D.Text(current, "upload_url"):gsub("{.*$", "") .. "?name=" .. encode(D.Text(asset, "name"))
			local uploaded = api.Request(upload, {
				Method = "POST",
				Body = Fs.readFile(root .. "/" .. D.Text(asset, "path")),
				ContentType = contentType(asset),
			})
			assert(assetMatches(uploaded, asset), "uploaded asset verification failed")
		end
		assertFresh()
		local ref = api.Request("/git/ref/tags/" .. version, { Missing = true })
		if ref and commit(api, ref) ~= sha then
			api.JSON("PATCH", "/git/refs/tags/" .. version, C.Object({ sha = sha, force = true }))
		end
		if not ref then
			api.JSON("POST", "/git/refs", C.Object({ ref = "refs/tags/" .. version, sha = sha }))
		end
		assert(checkAssets(api.Pages(route .. "/assets"), true), "release assets differ from prepared version")
		api.JSON(
			"PATCH",
			route,
			C.Object({
				draft = false,
				discussion_category_name = "Announcements",
				make_latest = if identity.prerelease then "false" else "legacy",
			})
		)
		local published = assert(api.Request(route))
		assert(
			D.Get(published, "draft") == false
				and matches(published)
				and commit(api, api.Request("/git/ref/tags/" .. version)) == sha
				and checkAssets(api.Pages(route .. "/assets"), true),
			"published version verification failed"
		)
	end)
	if not ok then
		if created and release then
			local clean, cleanup = pcall(function()
				local route = "/releases/" .. D.Number(assert(release), "id")
				local current = api.Request(route, { Missing = true })
				if current and D.Get(current, "draft") == true and matches(current) then
					api.Request(route, { Method = "DELETE" })
				end
			end)
			assert(clean, tostring(failure) .. "; draft cleanup failed: " .. tostring(cleanup))
		end
		error(failure)
	end
end

function Publish.Selected(version: string)
	Authorization.Authorize()
	Versions.Parse(version)
	assert(Process.env.GH_TOKEN, "missing automatic workflow token")
	local repository = assert(Process.env.GITHUB_REPOSITORY)
	local api = Client.new(repository)
	Protection.Require(repository, api)
	local root = "build/releases/" .. version
	local metadata, publication = D.Read(root .. "/release.json"), D.Read(root .. "/publication.json")
	assert(
		D.Get(metadata, "version") == version
			and D.Get(publication, "version") == version
			and D.Equal(D.Get(metadata, "source_sha"), D.Get(publication, "source_sha"))
			and D.Get(publication, "controller_sha") == Process.env.GITHUB_SHA,
		"release controller/source mismatch"
	)
	local publicTargets: { C.Value } = {}
	local expectedAssets: { C.Value } = {}
	for _, target in D.Items(publication, "targets") do
		table.insert(publicTargets, D.Set(target, "contract", nil))
		local contract = D.Required(target, "contract")
		assert(
			D.Get(contract, "accepted") and D.Equal(D.Get(contract, "source_sha"), D.Get(metadata, "source_sha")),
			"release requires accepted admin validation"
		)
		local name = Shape.Relative(D.Text(target, "name"))
		local acceptedRoot = "build/tmp/receipts/publication/" .. version .. "/" .. name
		Hosted.Restore(contract, acceptedRoot)
		local expected = Distributions.Verify(acceptedRoot, contract)
		local packaged = Distributions.Verify(root .. "/packages/" .. name, contract)
		assert(
			D.Equal(expected.manifest, packaged.manifest) and D.Equal(D.Get(target, "manifest"), packaged.manifest),
			"published packages differ from accepted validation"
		)
		for _, item in Json.Array(packaged.manifest) do
			local path = Shape.Relative(D.Text(item, "path"))
			local bytes = Fs.readFile(root .. "/packages/" .. name .. "/" .. path)
			if Render.Executable(bytes) then
				local file = "executables/" .. name .. "-" .. path:gsub("/", "-")
				table.insert(
					expectedAssets,
					C.Object({
						path = file,
						name = version .. "-" .. assert(file:match("([^/]+)$")),
						sha256 = Serde.hash("sha256", bytes),
					})
				)
			end
		end
	end
	assert(
		D.Equal(C.Array(publicTargets), D.Get(metadata, "targets")),
		"public build identities differ from accepted validation"
	)
	assert(D.Equal(C.Array(expectedAssets), D.Get(metadata, "assets")), "executable assets differ from accepted builds")
	Publish.Version(api, metadata, root, function()
		local source = D.Required(assert(api.Request("/git/ref/heads/source")), "object")
		assert(
			D.Equal(D.Get(source, "sha"), D.Get(publication, "controller_sha")),
			"stale release run: source advanced"
		)
		local contract =
			assert(api.Request("/contents/publication/releases/versions.toml?ref=" .. D.Text(source, "sha")))
		assert(
			Serde.hash("sha256", Base64.Decode(D.Text(contract, "content"):gsub("%s", "")))
				== D.Get(publication, "contract_hash"),
			"release selection changed after assembly"
		)
		Protection.Require(repository, api)
	end)
end

function Publish.Run()
	Publish.Selected(assert(Process.env.RELEASE_VERSION or Process.args[1], "release version required"))
end

return Publish
