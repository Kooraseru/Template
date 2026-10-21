-- ci/publication/releases/plan.luau
--!strict

local Plan = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Process = require("@lune/process")
local Rules = require("../../libraries/registry/rules")
local Canonical = require("../../libraries/bootstrap/canonical")
local Git = require("../../libraries/bootstrap/git")
local GitHub = require("../../libraries/bootstrap/github")
local Base64 = require("../../libraries/bootstrap/base64")
local Identity = require("../../security/receipts/identity")
local Versions = require("./versions")
local Request = require("../../integration/request")

--# Helpers

local function arrayValue(raw: unknown): Canonical.Array
	local values = {}

	for _, value in Rules.Array(raw) do
		table.insert(values, Canonical.FromLune(value))
	end

	return Canonical.Array(values)
end

local function write(path: string, value: Canonical.Value)
	Fs.writeDir("build/tmp/releases")
	Fs.writeFile(path, assert(Canonical.Encode(value)) .. "\n")
end

local function imageArtifact(raw: unknown, recipes: unknown): string
	local definition = Rules.Entries(raw)
	assert(type(definition.name) == "string", "missing image identity")
	local value = Canonical.Object({ definition = Canonical.FromLune(raw), recipes = Canonical.FromLune(recipes) })

	return "image-" .. definition.name .. "-" .. Canonical.Hash(value):sub(1, 24)
end

--# Functions

function Plan.SourceTip(): string
	if Process.env.ACT == "true" or Process.env.GITHUB_ACTIONS ~= "true" then
		if Git.Text({ "branch", "--show-current" }) == "source" then
			return Git.FullSHA(Git.Text({ "rev-parse", "HEAD" }))
		end

		local success, tip = pcall(function()
			return Git.Text({ "rev-parse", "refs/remotes/origin/source" })
		end)

		return Git.FullSHA(if success then tip else Git.Text({ "rev-parse", "HEAD" }))
	end

	local repository = Process.env.GITHUB_REPOSITORY

	if Process.env.GH_TOKEN and repository then
		local ref = Rules.Entries(GitHub.Api("repos/" .. repository .. "/git/ref/heads/source"))

		return Git.FullSHA(Rules.Entries(ref.object).sha)
	end

	local tip = Git.Text({ "ls-remote", "origin", "refs/heads/source" }):match("^(%S+)")

	return Git.FullSHA(tip)
end

function Plan.Selections(raw: unknown, enabled: boolean, controls: Request.Controls): { Versions.Selection }
	local tip = Plan.SourceTip()

	if Process.env.ACT ~= "true" and Process.env.GITHUB_ACTIONS == "true" then
		local env: { [string]: string } = {}

		if Process.env.GH_TOKEN then
			env.GIT_CONFIG_COUNT = "1"
			env.GIT_CONFIG_KEY_0 = "http.https://github.com/.extraheader"
			env.GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic " .. Base64.Encode("x-access-token:" .. Process.env.GH_TOKEN)
		end

		Git.Bytes({ "fetch", "--no-tags", "origin", tip }, nil, env)
	end

	return if enabled then Versions.Select(raw, controls, tip) else {}
end

function Plan.FingerprintInput(entry: Rules.Dictionary, controllerHash: string): Canonical.Object
	local target: { [string]: Canonical.Value } = {}

	for _, key in
		{
			"name",
			"runner",
			"target",
			"profile",
			"environment",
			"probes",
			"rust_version",
			"msvc_arch",
			"reuse_identity",
		}
	do
		if entry[key] ~= nil then
			target[key] = Canonical.FromLune(entry[key])
		end
	end

	target.reproducible = entry.reproducible == true
	local fields: { [string]: Canonical.Value } = {
		controllerHash = controllerHash,
		target = Canonical.Object(target),
		image = if entry.image_definition then Canonical.FromLune(entry.image_definition) else Canonical.Null,
	}

	for _, key in { "build", "recipes", "project_targets" } do
		if entry[key] ~= nil then
			fields[key] = Canonical.FromLune(entry[key])
		end
	end

	return Canonical.Object(fields)
end

function Plan.Finalize(raw: unknown): (Rules.Dictionary, { [string]: string })
	local plan = table.clone(Rules.Entries(raw))
	local sha = Git.FullSHA(plan.controller_sha)
	local paths: { string } = {}
	local objectsByPath: { [string]: string } = {}

	for _, line in
		Git.Bytes({
			"ls-tree",
			"-r",
			"-z",
			sha,
			"ci",
			".github",
			"config",
			"libraries",
			"validation",
			"fabricator",
			"security",
			"publication",
		}):split("\0")
	do
		if line == "" then
			continue
		end
		local kind, oid, file = line:match("^%d+ (%w+) ([a-f0-9]+)\t(.*)$")
		assert(kind == "blob" and oid and file, "invalid controller input")
		objectsByPath[file] = oid
		if
			file ~= ""
			and not file:find("README", 1, true)
			and not file:match("%.md$")
			and not file:match("config%.toml$")
			and not file:match("versions%.toml$")
			and not file:find("records/", 1, true)
		then
			table.insert(paths, file)
		end
	end

	table.sort(paths)
	local controllerFiles: { Canonical.Value } = {}
	local objects = {}

	for _, file in paths do
		table.insert(objects, objectsByPath[file])
	end
	local blobs = Git.Blobs(objects)

	for index, file in paths do
		table.insert(controllerFiles, Canonical.Array({ file, Serde.hash("sha256", blobs[index]) }))
	end

	local controllerHash = Canonical.Hash(Canonical.Array(controllerFiles))
	local builds = {}
	local identities: { [string]: Identity.Snapshot } = {}

	for _, rawEntry in Rules.Array(plan.builds) do
		local entry = table.clone(Rules.Entries(rawEntry))
		entry.reuse_identity = entry.reuse_identity or "exact_commit"
		assert(
			entry.reuse_identity == "exact_commit" or entry.reuse_identity == "source_tree",
			"Invalid target reuse identity"
		)
		assert(
			entry.reproducible == nil or type(entry.reproducible) == "boolean",
			"Reproducible declaration must be boolean"
		)
		local source = Git.FullSHA(entry.source_sha)
		local selected = identities[source] or Identity.Read(source)
		identities[source] = selected
		entry.tree = selected.tree
		entry.source_manifest_sha256 = selected.source_manifest_sha256
		entry.fingerprint = Canonical.Hash(Plan.FingerprintInput(entry, controllerHash))

		if entry.image_definition then
			entry.image_artifact = imageArtifact(entry.image_definition, entry.recipes)
		end

		entry.recipes = nil
		entry.cache_run = ""
		table.insert(builds, entry)
	end

	local images = {}
	local seen: { [string]: boolean } = {}

	for _, rawImage in Rules.Array(plan.images) do
		local image = table.clone(Rules.Entries(rawImage))
		local artifact = imageArtifact(image.definition, image.recipes)
		image.artifact = artifact
		image.definition = nil
		image.recipes = nil

		if not seen[artifact] then
			seen[artifact] = true
			table.insert(images, image)
		end
	end

	local selections = Rules.Array(plan.selections)
	plan.builds = builds
	plan.images = images
	plan.selections = selections
	plan.controller_hash = controllerHash
	local fields: { [string]: Canonical.Value } = {}

	for key, value in plan do
		assert(type(key) == "string", "invalid plan field")
		fields[key] = if key == "builds"
				or key == "images"
				or key == "selections"
			then arrayValue(value)
			else Canonical.FromLune(value)
	end

	local releaseMatrix = {}

	for _, value in selections do
		local selection = Rules.Entries(value)
		table.insert(releaseMatrix, { version = selection.version, type = selection.type })
	end

	local output = {
		build_matrix = assert(Canonical.Encode(Canonical.Object({ include = arrayValue(builds) }))),
		image_matrix = assert(Canonical.Encode(Canonical.Object({ include = arrayValue(images) }))),
		release_matrix = assert(Canonical.Encode(Canonical.Object({ include = arrayValue(releaseMatrix) }))),
		images_enabled = tostring(#images > 0),
	}
	write("build/tmp/releases/plan.json", Canonical.Object(fields))
	write("build/tmp/releases/outputs.json", Canonical.FromLune(output))

	return plan, output
end

return Plan
