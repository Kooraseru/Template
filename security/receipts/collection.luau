-- security/receipts/collection.luau
--!strict

local Collection = {}

--# Modules

local Fs = require("@lune/fs")
local Datetime = require("@lune/datetime")
local D = require("../../libraries/bootstrap/documents")
local C = require("../../libraries/bootstrap/canonical")
local Json = require("../../libraries/bootstrap/json")
local Bundles = require("../../libraries/bootstrap/bundles")
local Files = require("../../libraries/bootstrap/files")
local Git = require("../../libraries/bootstrap/git")
local Shape = require("../../libraries/registry/shape")
local Identity = require("./identity")
local Verification = require("./verification")
local Distributions = require("../../publication/releases/distributions")

--# Functions

function Collection.Clean()
	assert(Git.Text({ "status", "--porcelain", "--untracked-files=all" }) == "", "committed clean checkout required")
end

function Collection.Collect(plan: C.Value, distributions: string, logs: string, context: C.Value): C.Object
	Collection.Clean()
	local builds = D.Items(plan, "builds")
	if #builds == 1 then
		local entry = builds[1]
		Bundles.Normalize(distributions, D.Text(entry, "artifact"), "provenance.json")
		if Fs.isDir(logs) then
			for _, name in Fs.readDir(logs) do
				if name:match("%.log$") then
					Bundles.Normalize(
						logs,
						"build-logs-" .. D.Text(entry, "source_sha") .. "-" .. D.Text(entry, "name"),
						name
					)
					break
				end
			end
		end
	end
	local source = Identity.Read(D.Text(context, "tested_sha"))
	local targets: { C.Value } = {}
	local required: { C.Value } = {}
	for _, entry in builds do
		table.insert(
			required,
			C.Object({ name = D.Required(entry, "name"), source_sha = D.Required(entry, "source_sha") })
		)
		local root = distributions .. "/" .. Shape.Relative(D.Text(entry, "artifact"))
		if not Fs.isDir(root) and D.Get(context, "local") == true then
			continue
		end
		local verified = Distributions.Verify(root, entry)
		local selected = D.From(Identity.Read(D.Text(verified.metadata, "source_sha")))
		local logName = "build-logs-" .. D.Text(entry, "source_sha") .. "-" .. D.Text(entry, "name")
		local logFiles = Bundles.Manifest(logs .. "/" .. Shape.Relative(logName))
		assert(#logFiles.items > 0, "build logs missing")
		local fields = Json.Fields(selected)
		for _, key in { "name", "fingerprint", "reuse_identity", "artifact" } do
			fields[key] = D.Required(entry, key)
		end
		fields.files = Bundles.Manifest(root)
		fields.logs = logFiles
		fields.log_artifact = logName
		fields.result = "success"
		fields.reproducible = D.Get(entry, "reproducible") == true
		fields.execution = D.Required(verified.metadata, "execution")
		fields.resolved_fingerprint = D.Required(verified.metadata, "resolved_fingerprint")
		table.insert(targets, C.Object(fields))
	end
	local controls = D.Get(context, "controls") or C.Object({})
	local validation = D.Get(plan, "validation")
	local receipt = C.Object({
		schema = 1,
		repository = D.Required(context, "repository"),
		tested_sha = source.source_sha,
		tree = source.tree,
		source_manifest_sha256 = source.source_manifest_sha256,
		controller_hash = D.Required(plan, "controller_hash"),
		controller_sha = D.Required(plan, "controller_sha"),
		created_at = Datetime.now():toIsoDate(),
		pr = D.Required(context, "pr"),
		targets = C.Array(targets),
		required_targets = C.Array(required),
		partial = #targets ~= #builds,
		diagnostic = D.Get(context, "diagnostic") == true
			or (validation ~= nil and D.Get(validation, "success") == false),
		validation_scope = D.Get(controls, "validation_scope") or "All",
		controls = controls,
		source_authorization = D.Get(context, "source_authorization") or C.Missing,
	})
	return Verification.Validate(receipt)
end

function Collection.Bundle(root: string, receipt: C.Value, distributions: string, logs: string)
	assert(not Fs.metadata(root).exists, "receipt bundle destination must be fresh")
	Fs.writeDir(root)
	for _, target in D.Items(receipt, "targets") do
		local artifact = Shape.Relative(D.Text(target, "artifact"))
		local log = Shape.Relative(D.Text(target, "log_artifact"))
		Files.Copy(distributions .. "/" .. artifact, root .. "/distributions/" .. artifact)
		Files.Copy(logs .. "/" .. log, root .. "/logs/" .. log)
	end
end

function Collection.VerifyBundle(root: string, receipt: C.Value)
	Verification.Validate(receipt)
	local expected: { C.Value } = {}
	for _, target in D.Items(receipt, "targets") do
		local artifact = Shape.Relative(D.Text(target, "artifact"))
		local log = Shape.Relative(D.Text(target, "log_artifact"))
		local verified = Distributions.Verify(root .. "/distributions/" .. artifact, target)
		for _, field in { "tree", "source_manifest_sha256", "resolved_fingerprint", "execution" } do
			assert(
				D.Equal(D.Get(verified.metadata, field), D.Get(target, field)),
				"distribution evidence differs from receipt: " .. field
			)
		end
		local logFiles = D.Items(target, "logs")
		for _, probe in Json.Array(D.Get(D.Required(target, "execution"), "probe_logs") or C.Array({})) do
			local found = false
			for _, file in logFiles do
				found = found or D.Equal(file, probe)
			end
			assert(found, "toolchain probe evidence missing")
		end
		for _, group in
			{
				{ "distributions/" .. artifact .. "/", D.Required(target, "files") },
				{ "logs/" .. log .. "/", D.Required(target, "logs") },
			}
		do
			local prefix = Json.String(group[1])
			Bundles.VerifyFiles(root .. "/" .. prefix, group[2])
			for _, file in Json.Array(group[2]) do
				table.insert(expected, D.Set(file, "path", prefix .. D.Text(file, "path")))
			end
		end
	end
	Bundles.VerifyFiles(root, C.Array(expected))
end

return Collection
