-- security/receipts/hosted.luau
--!strict

local Hosted = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Datetime = require("@lune/datetime")
local C = require("../../libraries/bootstrap/canonical")
local D = require("../../libraries/bootstrap/documents")
local Json = require("../../libraries/bootstrap/json")
local Base64 = require("../../libraries/bootstrap/base64")
local Native = require("../../libraries/bootstrap/native")
local GitHub = require("../../libraries/bootstrap/github")
local Commands = require("../../libraries/bootstrap/commands")
local Files = require("../../libraries/bootstrap/files")
local Bundles = require("../../libraries/bootstrap/bundles")
local Shape = require("../../libraries/registry/shape")
local Request = require("../../.github/integration/request")
local Pending = require("../../.github/integration/pending-receipt")
local Client = require("../../publication/releases/client")
local Authentication = require("./authentication")
local Verification = require("./verification")
local Collection = require("./collection")

--# Helpers

local function api(): Client.API
	return Client.new(GitHub.Repository())
end

local function policy(): C.Value
	return D.Required(D.Read("security/receipts/ruleset.json"), "rules")
end

local function temporary(category: string): string
	return "build/tmp/receipts/" .. category .. "/" .. Native.UUID()
end

local function findAsset(release: C.Value, name: string): C.Value
	for _, asset in D.Items(release, "assets") do
		if D.Get(asset, "name") == name then
			return asset
		end
	end
	error("missing staging asset: " .. name)
end

--# Functions

function Hosted.CurrentPR(number: number): C.Value
	assert(number > 0 and number % 1 == 0, "invalid PR number")
	local pr = assert(api().Request("/pulls/" .. number))
	local base = D.Required(pr, "base")
	assert(
		D.Get(pr, "state") == "open"
			and D.Get(base, "ref") == "source"
			and D.Text(D.Required(base, "repo"), "full_name"):lower() == GitHub.Repository():lower(),
		"open source PR required"
	)
	return C.Object({
		number = D.Required(pr, "number"),
		head_sha = D.Required(D.Required(pr, "head"), "sha"),
		base_sha = D.Required(base, "sha"),
	})
end

function Hosted.AssertAdminWriters()
	for _, user in api().Pages("/collaborators?affiliation=all") do
		local permissions = D.Required(user, "permissions")
		assert(
			D.Get(permissions, "push") ~= true or D.Get(permissions, "admin") == true,
			"non-admin repository write access violates the receipt trust boundary"
		)
	end
end

function Hosted.PredatesContract(sha: string): boolean
	assert(#sha == 40 and sha:match("^[a-f0-9]+$"), "full base SHA required")
	for _, raw in D.Items(policy(), "contract_paths") do
		if api().Request("/contents/" .. Json.String(raw) .. "?ref=" .. sha, { Missing = true }) then
			return false
		end
	end
	return true
end

function Hosted.Download(asset: C.Value, output: string)
	local bytes = assert(api().Bytes("/releases/assets/" .. D.Number(asset, "id"), { Binary = true }))
	local digest = D.Get(asset, "digest")
	assert(
		#bytes == D.Number(asset, "size")
			and (not Json.Truthy(digest) or digest == "sha256:" .. Serde.hash("sha256", bytes)),
		"downloaded asset size or checksum mismatch"
	)
	Fs.writeDir(assert(output:match("^(.*)/[^/]+$")))
	Fs.writeFile(output, bytes)
end

function Hosted.VerifyEnvelope(envelope: C.Value): Authentication.Accepted
	local keysResponse = api().Request("/contents/security/receipts/keys.json?ref=source", { Missing = true })
	local keys = if keysResponse
		then C.Decode(Base64.Decode(D.Text(keysResponse, "content"):gsub("%s", "")))
		else C.Object({ schema = 1, keys = C.Array({}) })
	return Authentication.Authenticate(envelope, {
		Repository = GitHub.Repository(),
		Keys = keys,
		IsAdmin = GitHub.IsAdmin,
		HostedRun = function(id)
			local runID = if type(id) == "number" then tostring(id) else Json.String(id)
			assert(runID:match("^%d+$"), "invalid run ID")
			local run = assert(api().Request("/actions/runs/" .. runID))
			local root = temporary("hosted")
			Fs.writeDir(root)
			Commands.Run("gh", {
				"run",
				"download",
				runID,
				"--repo",
				GitHub.Repository(),
				"--name",
				"validation-receipt",
				"--dir",
				root,
			})
			assert(
				D.Equal(D.Read(root .. "/receipt.json"), envelope),
				"hosted receipt differs from reporting run artifact"
			)
			return run
		end,
		AllowBootstrap = function(raw, run)
			local receipt = D.Required(raw, "receipt")
			local pr = D.Required(receipt, "pr")
			local head = D.Text(run, "head_sha")
			if
				D.Number(pr, "number") < 1
				or D.Get(pr, "head_sha") ~= head
				or D.Get(receipt, "tested_sha") ~= head
				or D.Get(receipt, "controller_sha") ~= head
				or not Hosted.PredatesContract(D.Text(pr, "base_sha"))
			then
				return false
			end
			local current = assert(api().Request("/pulls/" .. D.Number(pr, "number")))
			local source = D.Required(current, "head")
			return D.Get(D.Required(current, "base"), "ref") == "source"
				and D.Get(source, "sha") == head
				and D.Text(D.Required(source, "repo"), "full_name"):lower() == GitHub.Repository():lower()
		end,
		AllowPendingRun = function(run)
			return Pending.Allowed(D.Plain(run)) and GitHub.IsAdmin(GitHub.Actor())
		end,
		AllowDiagnostic = function(receipt)
			return Request.DiagnosticReuseAllowed(D.Plain(receipt))
		end,
	})
end

function Hosted.ListStaging(): { C.Value }
	local result: { C.Value } = {}
	local prefix = D.Text(policy(), "staging_prefix")
	for _, release in api().Pages("/releases") do
		if D.Get(release, "draft") == true and D.Text(release, "tag_name"):sub(1, #prefix) == prefix then
			table.insert(result, release)
		end
	end
	table.sort(result, function(a, b)
		return D.Number(a, "id") > D.Number(b, "id")
	end)
	return result
end

function Hosted.FreshPR(receipt: C.Value)
	local pr = D.Required(receipt, "pr")
	if D.Number(pr, "number") > 0 then
		assert(D.Equal(Hosted.CurrentPR(D.Number(pr, "number")), pr), "PR head or base changed")
	end
end

function Hosted.Discover(
	plan: C.Value,
	pr: C.Value?,
	materialize: boolean?
): { Plan: C.Value, Accepted: { C.Value }, Rejected: { string } }
	local candidates: { { Release: C.Value, Archive: C.Value, Envelope: C.Value, Receipt: C.Value, Validator: string, Root: string } } =
		{}
	local rejected: { string } = {}
	local config = policy()
	for _, release in Hosted.ListStaging() do
		local ok, failure = pcall(function()
			local receiptAsset = findAsset(release, D.Text(config, "receipt_asset"))
			local archive = findAsset(release, D.Text(config, "archive_asset"))
			assert(
				D.Number(archive, "size") <= D.Number(config, "max_archive_bytes"),
				"staging archive exceeds size limit"
			)
			local root = temporary("discovery")
			Hosted.Download(receiptAsset, root .. "/receipt.json")
			local envelope = D.Read(root .. "/receipt.json")
			local accepted = Hosted.VerifyEnvelope(envelope)
			if
				not D.Equal(D.Get(accepted.receipt, "controller_hash"), D.Get(plan, "controller_hash"))
				or (pr and not D.Equal(pr, D.Get(accepted.receipt, "pr")))
			then
				return
			end
			Hosted.Download(archive, root .. "/bundle.tar.gz")
			assert(
				Serde.hash("sha256", Fs.readFile(root .. "/bundle.tar.gz")) == D.Text(accepted.receipt, "bundle_sha256"),
				"archive differs from signed receipt"
			)
			Bundles.Unpack(root .. "/bundle.tar.gz", root .. "/bundle")
			Collection.VerifyBundle(root .. "/bundle", accepted.receipt)
			table.insert(candidates, {
				Release = release,
				Archive = archive,
				Envelope = envelope,
				Receipt = accepted.receipt,
				Validator = accepted.validator,
				Root = root .. "/bundle",
			})
		end)
		if not ok then
			table.insert(rejected, tostring(failure))
		end
	end
	local builds: { C.Value } = {}
	local accepted: { C.Value } = {}
	for _, original in D.Items(plan, "builds") do
		local entry = original
		for _, candidate in candidates do
			local target: C.Value? = nil
			for _, item in D.Items(candidate.Receipt, "targets") do
				if Verification.Applicable(item, entry) and Verification.ExecutionValid(item, entry) then
					target = item
					break
				end
			end
			if not target then
				continue
			end
			entry = D.Set(
				entry,
				"accepted",
				C.Object({
					release_id = D.Required(candidate.Release, "id"),
					asset_id = D.Required(candidate.Archive, "id"),
					archive_sha256 = D.Required(candidate.Receipt, "bundle_sha256"),
					source_sha = D.Required(target, "source_sha"),
					resolved_fingerprint = D.Required(target, "resolved_fingerprint"),
					artifact = D.Required(target, "artifact"),
					envelope = C.Hash(candidate.Envelope),
				})
			)
			if materialize then
				Files.Copy(
					candidate.Root .. "/distributions/" .. Shape.Relative(D.Text(target, "artifact")),
					"build/accepted-distributions/" .. Shape.Relative(D.Text(entry, "artifact"))
				)
				Files.Copy(
					candidate.Root .. "/logs/" .. Shape.Relative(D.Text(target, "log_artifact")),
					"build/accepted-logs/build-logs-"
						.. D.Text(entry, "source_sha")
						.. "-"
						.. Shape.Relative(D.Text(entry, "name"))
				)
			end
			table.insert(
				accepted,
				C.Object({
					name = D.Required(entry, "name"),
					selected_sha = D.Required(entry, "source_sha"),
					tested_sha = D.Required(target, "source_sha"),
					release_id = D.Required(candidate.Release, "id"),
					validator = candidate.Validator,
				})
			)
			break
		end
		table.insert(builds, entry)
	end
	return { Plan = D.Set(plan, "builds", C.Array(builds)), Accepted = accepted, Rejected = rejected }
end

function Hosted.Restore(entry: C.Value, destination: string): C.Value
	local acceptance = D.Required(entry, "accepted")
	local release = assert(api().Request("/releases/" .. D.Number(acceptance, "release_id")))
	local prefix = D.Text(policy(), "staging_prefix")
	assert(
		D.Get(release, "draft") == true and D.Text(release, "tag_name"):sub(1, #prefix) == prefix,
		"staging release no longer valid"
	)
	local root = temporary("restore")
	Hosted.Download(findAsset(release, "receipt.json"), root .. "/receipt.json")
	local envelope = D.Read(root .. "/receipt.json")
	assert(C.Hash(envelope) == D.Text(acceptance, "envelope"), "staging receipt changed")
	local receipt = Hosted.VerifyEnvelope(envelope).receipt
	local target: C.Value? = nil
	for _, item in D.Items(receipt, "targets") do
		if Verification.Applicable(item, entry) and Verification.ExecutionValid(item, entry) then
			target = item
			break
		end
	end
	assert(target, "receipt no longer matches selected build")
	local archive: C.Value? = nil
	for _, asset in D.Items(release, "assets") do
		if D.Equal(D.Get(asset, "id"), D.Get(acceptance, "asset_id")) then
			archive = asset
			break
		end
	end
	assert(
		archive and D.Number(archive, "size") <= D.Number(policy(), "max_archive_bytes"),
		"staging archive missing or oversized"
	)
	Hosted.Download(archive, root .. "/bundle.tar.gz")
	assert(
		Serde.hash("sha256", Fs.readFile(root .. "/bundle.tar.gz")) == D.Text(receipt, "bundle_sha256"),
		"staging archive changed"
	)
	Bundles.Unpack(root .. "/bundle.tar.gz", root .. "/bundle")
	Collection.VerifyBundle(root .. "/bundle", receipt)
	Files.Copy(root .. "/bundle/distributions/" .. Shape.Relative(D.Text(target, "artifact")), destination)
	Files.Copy(root .. "/bundle/logs/" .. Shape.Relative(D.Text(target, "log_artifact")), "build/logs")
	return target
end

function Hosted.Upload(envelope: C.Value, archive: string): C.Value
	assert(GitHub.IsAdmin(GitHub.Actor()), "only administrators may stage validation")
	assert(#Fs.readFile(archive) <= D.Number(policy(), "max_archive_bytes"), "validation archive exceeds size limit")
	local prefix = D.Text(policy(), "staging_prefix")
	for _, release in Hosted.ListStaging() do
		local tag = D.Text(release, "tag_name")
		local age = Datetime.now().unixTimestampMillis
			- Datetime.fromRfc3339(D.Text(release, "created_at")).unixTimestampMillis
		if
			age > D.Number(policy(), "retention_days") * 86400000
			and tag:sub(1, #prefix) == prefix
			and #tag == #prefix + 36
			and tag:sub(#prefix + 1):match("^[a-f0-9%-]+$")
		then
			api().Request("/releases/" .. D.Number(release, "id"), { Method = "DELETE" })
		end
	end
	local tag = prefix .. Native.UUID()
	local root = "build/tmp/receipts/upload/" .. tag
	D.Write(root .. "/receipt.json", envelope)
	Files.Copy(archive, root .. "/bundle.tar.gz")
	local release = api().JSON(
		"POST",
		"/releases",
		C.Object({
			tag_name = tag,
			target_commitish = D.Required(D.Required(envelope, "receipt"), "controller_sha"),
			name = tag,
			draft = true,
			body = "Internal validation staging. Expires after 30 days.",
		})
	)
	local ok, result = pcall(function()
		Commands.Run("gh", {
			"release",
			"upload",
			tag,
			root .. "/receipt.json",
			root .. "/bundle.tar.gz",
			"--repo",
			GitHub.Repository(),
		})
		local refreshed = assert(api().Request("/releases/" .. D.Number(release, "id")))
		for _, name in { "receipt.json", "bundle.tar.gz" } do
			Hosted.Download(findAsset(refreshed, name), root .. "/verified/" .. name)
			assert(
				Serde.hash("sha256", Fs.readFile(root .. "/verified/" .. name))
					== Serde.hash("sha256", Fs.readFile(root .. "/" .. name)),
				"upload verification failed"
			)
		end
		return refreshed
	end)
	if not ok then
		local clean, failure = pcall(function()
			api().Request("/releases/" .. D.Number(release, "id"), { Method = "DELETE" })
		end)
		assert(clean, tostring(result) .. "; staging cleanup failed: " .. tostring(failure))
		error(result)
	end
	return result
end

function Hosted.SetCheck(sha: string, conclusion: string, summary: string)
	assert(
		Process.env.ACT ~= "true" and Process.env.GITHUB_ACTIONS == "true" and Process.env.GH_TOKEN,
		"official checks require trusted Actions"
	)
	api().JSON(
		"POST",
		"/check-runs",
		C.Object({
			name = "gate",
			head_sha = sha,
			status = "completed",
			conclusion = conclusion,
			output = C.Object({
				title = if conclusion == "success" then "Admin validation accepted" else "Admin validation required",
				summary = summary,
			}),
		})
	)
end

return Hosted
