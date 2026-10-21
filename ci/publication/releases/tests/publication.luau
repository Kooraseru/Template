-- publication/releases/tests/publication.luau
--!strict

local Test = require("@testing")

--# Modules

local Json = require("../../../libraries/bootstrap/json")
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local C = require("../../../libraries/bootstrap/canonical")
local D = require("../../../libraries/bootstrap/documents")
local Files = require("../../../libraries/bootstrap/files")
local Client = require("../client")
local Publish = require("../publish")
local Versions = require("../versions")
local Render = require("../render")

--# Types

type State = {
	Releases: { [string]: C.Value },
	Refs: { [string]: C.Value },
	Bytes: { [number]: string },
	Sequence: number,
	Writes: number,
	FailUpload: boolean,
	BadDigest: boolean,
	NoDigest: boolean,
	LosePromotion: boolean,
	FailVerification: boolean,
}
type Input = string

--# Helpers

local function fixture(): (Client.API, State)
	local state: State = {
		Releases = {},
		Refs = {},
		Bytes = {},
		Sequence = 1,
		Writes = 0,
		FailUpload = false,
		BadDigest = false,
		NoDigest = false,
		LosePromotion = false,
		FailVerification = false,
	}
	local function find(id: number): (string, C.Value)
		for tag, release in state.Releases do
			if D.Number(release, "id") == id then
				return tag, release
			end
		end
		error("missing fake release")
	end
	local function json(method: string, route: string, value: C.Value): C.Value
		state.Writes += 1
		if route == "/releases" and method == "POST" then
			local id = state.Sequence
			state.Sequence += 1
			local release = D.Set(
				D.Set(
					D.Set(value, "id", id),
					"upload_url",
					"https://uploads.github.com/repos/fixture/releases/" .. id .. "{?name}"
				),
				"assets",
				C.Array({})
			)
			state.Releases[D.Text(value, "tag_name")] = release
			return release
		elseif route == "/git/refs" then
			local tag = D.Text(value, "ref"):gsub("^refs/tags/", "")
			state.Refs[tag] = C.Object({ object = C.Object({ type = "commit", sha = D.Required(value, "sha") }) })
			return state.Refs[tag]
		elseif route:match("^/git/refs/tags/") then
			local tag = route:gsub("^/git/refs/tags/", "")
			state.Refs[tag] = C.Object({ object = C.Object({ type = "commit", sha = D.Required(value, "sha") }) })
			return state.Refs[tag]
		end
		local id = assert(tonumber(route:match("^/releases/(%d+)$")))
		local tag, release = find(id)
		for key, field in Json.Fields(value) do
			release = D.Set(release, key, field)
		end
		if D.Get(value, "discussion_category_name") then
			release = D.Set(release, "discussion_url", "https://github.com/fixture/discussions/1")
		end
		state.Releases[tag] = release
		if state.LosePromotion and D.Get(value, "draft") == false then
			state.LosePromotion = false
			error("lost promotion response")
		end
		return release
	end
	local function request(route: string, options: Client.Options?): C.Value?
		local selected: Client.Options = options or {}
		if route:match("^https://uploads%.github%.com/") then
			state.Writes += 1
			assert(not state.FailUpload, "upload failed")
			local id, name = route:match("/(%d+)%?name=(.+)$")
			local tag, release = find(assert(tonumber(id)))
			local bytes = assert(selected.Body)
			local assetID = state.Sequence
			state.Sequence += 1
			state.Bytes[assetID] = bytes
			local asset = C.Object({
				id = assetID,
				name = assert(name),
				size = #bytes,
				content_type = assert(selected.ContentType),
				digest = if state.NoDigest
					then C.Null
					elseif state.BadDigest then "sha256:" .. string.rep("f", 64)
					else "sha256:" .. Serde.hash("sha256", bytes),
			})
			local assets = table.clone(D.Items(release, "assets"))
			table.insert(assets, asset)
			state.Releases[tag] = D.Set(release, "assets", C.Array(assets))
			return asset
		elseif route:match("^/git/ref/tags/") then
			return state.Refs[route:gsub("^/git/ref/tags/", "")]
		elseif route:match("^/git/tags/") then
			return C.Object({ object = C.Object({ type = "commit", sha = string.rep("a", 40) }) })
		elseif route:match("^/releases/tags/") then
			return state.Releases[route:gsub("^/releases/tags/", "")]
		elseif route:match("^/releases/assets/") then
			local id = assert(tonumber(route:match("(%d+)$")))
			assert(selected.Method == "DELETE", "expected asset deletion")
			state.Writes += 1
			for tag, release in state.Releases do
				local assets = {}
				for _, asset in D.Items(release, "assets") do
					if D.Get(asset, "id") ~= id then
						table.insert(assets, asset)
					end
				end
				state.Releases[tag] = D.Set(release, "assets", C.Array(assets))
			end
			state.Bytes[id] = nil
			return nil
		end
		local id = assert(tonumber(route:match("^/releases/(%d+)$")), "unexpected fake API route: " .. route)
		local found, tag, release = pcall(find, id)
		if not found and selected.Missing then
			return nil
		end
		assert(found, tostring(tag))
		if selected.Method == "DELETE" then
			state.Writes += 1
			state.Releases[tag] = nil
			return nil
		end
		if state.FailVerification and D.Get(release, "draft") == false then
			return D.Set(release, "name", "unexpected name")
		end
		return release
	end
	local api: Client.API = {
		Request = request,
		JSON = json,
		Pages = function(route)
			local _, release = find(assert(tonumber(route:match("^/releases/(%d+)/assets$"))))
			return table.clone(D.Items(release, "assets"))
		end,
		Bytes = function(route)
			return state.Bytes[assert(tonumber(route:match("/releases/assets/(%d+)$")))]
		end,
	}
	return api, state
end

local function prepare(version: string, payload: string?): (string, C.Value)
	local root = "build/tests/publication/" .. version
	Files.Reset(root)
	Fs.writeFile(root .. "/notes.md", "## What's Changed\n\nFixture changes.\n")
	local files = {}
	if payload then
		Fs.writeDir(root .. "/executables")
		Fs.writeFile(root .. "/executables/app.sh", payload)
		table.insert(files, "executables/app.sh")
	end
	local identity = Versions.Parse(version)
	local metadata = C.Object({

		version = version,
		prerelease = identity.prerelease,
		type = identity.type,
		source_sha = string.rep("a", 40),
		targets = C.Array({}),
	})
	return root, Render.FinalizeAssets(root, metadata, files)
end

local function execute(kind: Input): boolean
	local api, state = fixture()
	local root, metadata = prepare("1.2.0", "#!/bin/sh\necho original\n")
	local function publish()
		Publish.Version(api, metadata, root, function() end)
	end
	if kind == "types" then
		publish()
		local preRoot, pre = prepare("1.3.0-pre.1", nil)
		Publish.Version(api, pre, preRoot, function() end)
		assert(
			D.Get(state.Releases["1.2.0"], "prerelease") == false
				and D.Get(state.Releases["1.3.0-pre.1"], "prerelease") == true
		)
		assert(state.Refs["1.2.0"] and state.Refs["1.3.0-pre.1"])
	elseif kind == "no-op" then
		publish()
		local writes = state.Writes
		publish()
		assert(state.Writes == writes)
	elseif kind == "promotion" then
		local preRoot, pre = prepare("1.2.0-pre.1", nil)
		Publish.Version(api, pre, preRoot, function() end)
		local before = C.Hash(state.Releases["1.2.0-pre.1"])
		publish()
		assert(C.Hash(state.Releases["1.2.0-pre.1"]) == before)
	elseif kind == "replacement" then
		publish()
		local id = D.Number(state.Releases["1.2.0"], "id")
		root, metadata = prepare("1.2.0", "#!/bin/sh\necho changed\n")
		state.Refs["1.2.0"] = C.Object({ object = C.Object({ type = "commit", sha = string.rep("b", 40) }) })
		publish()
		assert(
			D.Number(state.Releases["1.2.0"], "id") == id
				and D.Get(D.Required(state.Refs["1.2.0"], "object"), "sha") == string.rep("a", 40)
		)
	elseif kind == "annotated" then
		state.Refs["1.2.0"] = C.Object({ object = C.Object({ type = "tag", sha = string.rep("c", 40) }) })
		publish()
		assert(D.Get(D.Required(state.Refs["1.2.0"], "object"), "type") == "tag")
	elseif kind == "history" then
		local oldRoot, old = prepare("0.1.0", nil)
		Publish.Version(api, old, oldRoot, function() end)
		local before = C.Hash(state.Releases["0.1.0"])
		local tag = C.Hash(state.Refs["0.1.0"])
		publish()
		assert(C.Hash(state.Releases["0.1.0"]) == before and C.Hash(state.Refs["0.1.0"]) == tag)
	elseif kind == "missing-digest" then
		state.NoDigest = true
		publish()
		local writes = state.Writes
		publish()
		assert(state.Writes == writes)
	elseif kind == "lost-promotion" then
		state.LosePromotion = true
		assert(not pcall(publish))
		assert(D.Get(state.Releases["1.2.0"], "draft") == false)
		local writes = state.Writes
		publish()
		assert(state.Writes == writes)
	elseif kind == "verification-failure" then
		state.FailVerification = true
		assert(not pcall(publish))
		assert(D.Get(state.Releases["1.2.0"], "draft") == false and state.Refs["1.2.0"])
	elseif kind == "stale-before" then
		assert(not pcall(Publish.Version, api, metadata, root, function(): ()
			error("source advanced")
		end))
		assert(state.Writes == 0)
	elseif kind == "source-only" then
		publish()
		root, metadata = prepare("1.2.0", nil)
		publish()
		assert(#D.Items(state.Releases["1.2.0"], "assets") == 0)
	elseif kind == "resume" then
		publish()
		state.Releases["1.2.0"] = D.Set(state.Releases["1.2.0"], "draft", true)
		publish()
		assert(D.Get(state.Releases["1.2.0"], "draft") == false)
	elseif kind == "stale-during" then
		local fresh = 0
		assert(not pcall(Publish.Version, api, metadata, root, function()
			fresh += 1
			assert(fresh < 2, "source advanced")
		end))
		assert(state.Refs["1.2.0"] == nil and state.Releases["1.2.0"] == nil)
	elseif kind == "changed-local" then
		Fs.writeFile(root .. "/executables/app.sh", "#!/bin/sh\nchanged after assembly\n")
		assert(not pcall(publish))
		assert(state.Writes == 0)
	elseif kind == "upload-failure" or kind == "bad-digest" then
		state.FailUpload = kind == "upload-failure"
		state.BadDigest = kind == "bad-digest"
		assert(not pcall(publish))
		assert(state.Releases["1.2.0"] == nil and state.Refs["1.2.0"] == nil)
	else
		error("unknown publication case")
	end
	return true
end

local function cases(): { Test.Case<Input, boolean> }
	local result: { Test.Case<Input, boolean> } = {}
	for _, kind in
		{
			"types",
			"no-op",
			"promotion",
			"replacement",
			"annotated",
			"history",
			"missing-digest",
			"lost-promotion",
			"verification-failure",
			"stale-before",
			"source-only",
			"resume",
			"stale-during",
			"changed-local",
			"upload-failure",
			"bad-digest",
		}
	do
		table.insert(result, { Name = kind, Input = kind, Expected = true })
	end
	return result
end

--# Declaration

local definition: Test.Definition<Input, boolean> =
	{ Name = "Replaceable public release publication", Execute = execute, Cases = cases() }

return Test.new(definition)
