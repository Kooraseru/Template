-- security/receipts/verification.luau
--!strict

local Verification = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Datetime = require("@lune/datetime")
local Rules = require("../../libraries/registry/rules")
local Canonical = require("../../libraries/bootstrap/canonical")
local Json = require("../../libraries/bootstrap/json")
local Config = require("../../libraries/registry/config")

--# Types

export type Policy = {
	retention_days: number,
	reuse_identities: { string },
	native_runners: { [string]: string },
	required_receipt_fields: { string },
	required_target_fields: { string },
	required_bundle_files: { string },
}

--# Helpers

local function strings(raw: unknown): { string }
	local values = {}

	for _, value in Rules.Array(raw) do
		assert(type(value) == "string", "invalid receipt policy string")
		table.insert(values, value)
	end

	return values
end

local function hex(value: Canonical.Value?, length: number): string
	local text = Json.String(value)
	assert(#text == length and text:match("^[a-f0-9]+$"), "invalid receipt digest or source identity")

	return text
end

local function required(fields: { [string]: Canonical.Value }, names: { string })
	for _, name in names do
		assert(fields[name] ~= nil, "missing receipt field: " .. name)
	end
end

local function timestamp(value: Canonical.Value?): number
	local text = Json.String(value)
	local success, date = pcall(Datetime.fromRfc3339, text)

	if success then
		return date.unixTimestampMillis
	end

	local rfcSuccess, rfc = pcall(Datetime.fromRfc2822, text)
	assert(rfcSuccess, "invalid receipt creation timestamp")

	return rfc.unixTimestampMillis
end

local function fieldEquals(a: { [string]: Canonical.Value }, b: { [string]: Canonical.Value }, name: string): boolean
	return a[name] ~= nil and b[name] ~= nil and Canonical.Encode(a[name]) == Canonical.Encode(b[name])
end

--# Functions

function Verification.Policy(): Policy
	local raw = Rules.Entries(Rules.Entries(Serde.decode("json", Fs.readFile("security/receipts/ruleset.json"))).rules)
	assert(type(raw.retention_days) == "number", "invalid receipt retention policy")
	local runners = {}

	for key, value in Rules.Entries(raw.native_runners) do
		assert(type(key) == "string" and type(value) == "string", "invalid native runner policy")
		runners[key] = value
	end

	return {

		retention_days = raw.retention_days,
		reuse_identities = strings(raw.reuse_identities),
		native_runners = runners,
		required_receipt_fields = strings(raw.required_receipt_fields),
		required_target_fields = strings(raw.required_target_fields),
		required_bundle_files = strings(raw.required_bundle_files),
	}
end

function Verification.Validate(value: Canonical.Value, now: number?): Canonical.Object
	local receipt = Json.Fields(value)
	assert(receipt.schema == nil, "receipt contains unsupported schema field")
	local policy = Verification.Policy()
	required(receipt, policy.required_receipt_fields)
	assert(Json.String(receipt.repository):match("^[^/%s]+/[^/%s]+$"), "invalid receipt repository")
	hex(receipt.tested_sha, 40)
	hex(receipt.tree, 40)
	hex(receipt.source_manifest_sha256, 64)
	hex(receipt.controller_hash, 64)
	local age = (now or Datetime.now().unixTimestampMillis) - timestamp(receipt.created_at)
	assert(age == age and age >= -300000 and age <= policy.retention_days * 86400000, "expired or future receipt")
	local pr = Json.Fields(receipt.pr)
	local number = Json.Number(pr.number)
	assert(number >= 0 and number < math.huge and number % 1 == 0, "invalid PR identity")
	hex(pr.head_sha, 40)
	hex(pr.base_sha, 40)
	local targets = Json.Array(receipt.targets)
	assert(#targets > 0, "no target coverage")
	local seen: { [string]: boolean } = {}

	for _, valueTarget in targets do
		local target = Json.Fields(valueTarget)
		required(target, policy.required_target_fields)
		local name = Json.String(target.name)
		local source = hex(target.source_sha, 40)
		assert(name:match("^[a-z0-9][a-z0-9%-]*$") and not seen[name .. ":" .. source], "invalid or duplicate target")
		seen[name .. ":" .. source] = true
		hex(target.tree, 40)
		hex(target.source_manifest_sha256, 64)
		hex(target.fingerprint, 64)
		assert(
			Json.String(target.resolved_fingerprint)
				== Canonical.Hash(Canonical.Object({ inputs = target.fingerprint, execution = target.execution })),
			"resolved execution fingerprint mismatch"
		)
		assert(
			table.find(policy.reuse_identities, Json.String(target.reuse_identity))
				and Json.String(target.result) == "success",
			"invalid or failed target"
		)
		local files, logs = Json.Array(target.files), Json.Array(target.logs)
		assert(#logs > 0, "execution logs required")
		local execution = Json.Fields(target.execution)
		assert(table.find({ "native", "container" }, Json.String(execution.kind)), "invalid execution kind")
		assert(table.find({ "linux", "win32", "darwin" }, Json.String(execution.os)), "invalid execution OS")
		assert(table.find({ "x64", "arm64" }, Json.String(execution.arch)), "invalid execution architecture")
		local available: { [string]: boolean } = {}

		for _, list in { files, logs } do
			for _, rawFile in list do
				local file = Json.Fields(rawFile)
				local path = Config.Relative(Json.String(file.path))
				hex(file.sha256, 64)

				if list == files then
					available[path] = true
				end
			end
		end

		for _, path in policy.required_bundle_files do
			assert(available[path], "incomplete target distribution")
		end
	end

	return Json.Object(value)
end

function Verification.Applicable(rawTarget: Canonical.Value, rawEntry: Canonical.Value): boolean
	local target, entry = Json.Fields(rawTarget), Json.Fields(rawEntry)

	for _, name in { "name", "fingerprint", "reuse_identity", "tree", "source_manifest_sha256" } do
		if not fieldEquals(target, entry, name) then
			return false
		end
	end

	return Json.String(target.result) == "success"
		and (Json.String(entry.reuse_identity) == "source_tree" or fieldEquals(target, entry, "source_sha"))
end

function Verification.ExecutionValid(rawTarget: Canonical.Value, rawEntry: Canonical.Value): boolean
	local target, entry = Json.Fields(rawTarget), Json.Fields(rawEntry)
	local execution = Json.Fields(target.execution)
	local runner = Json.String(entry.runner)
	local entryName = entry.name
	local name = if entryName then Json.String(entryName) else ""
	local nativeOS: string? = nil

	for prefix, os in Verification.Policy().native_runners do
		if runner:sub(1, #prefix) == prefix or name:sub(1, #prefix + 1) == prefix .. "-" then
			nativeOS = os
			break
		end
	end

	if not nativeOS then
		local platform = if Json.Truthy(entry.platform) then Json.String(entry.platform) else nil

		return Json.String(execution.os) == "linux"
			and (
				not platform
				or Json.String(execution.arch) == (if platform:sub(-5) == "arm64" then "arm64" else "x64")
			)
	end

	local selected = if Json.Truthy(entry.target) then Json.String(entry.target) else name
	local arch = if selected:find("arm64", 1, true) or selected:find("aarch64", 1, true) then "arm64" else "x64"

	return Json.String(execution.kind) == "native"
		and Json.String(execution.os) == nativeOS
		and Json.String(execution.arch) == arch
end

function Verification.Compare(
	rawClaim: Canonical.Value,
	rawAccepted: Canonical.Value,
	now: number?
): { Canonical.Value }
	local claim = Json.Fields(Verification.Validate(rawClaim, now))
	local accepted = Json.Fields(Verification.Validate(rawAccepted, now))

	for _, name in { "repository", "tested_sha", "controller_hash", "pr" } do
		assert(fieldEquals(claim, accepted, name), "claim inputs differ")
	end

	local differences: { Canonical.Value } = {}

	for _, valueOther in Json.Array(claim.targets) do
		local other = Json.Fields(valueOther)
		local matched: { [string]: Canonical.Value }? = nil

		for _, valueTarget in Json.Array(accepted.targets) do
			local target = Json.Fields(valueTarget)

			if fieldEquals(target, other, "name") and fieldEquals(target, other, "source_sha") then
				matched = target
				break
			end
		end

		assert(matched, "claim target is absent")

		for _, name in { "fingerprint", "tree", "source_manifest_sha256", "result", "resolved_fingerprint" } do
			assert(fieldEquals(other, matched, name), "claim target inputs, resolved environment, or outcomes differ")
		end

		if not fieldEquals(other, matched, "files") then
			assert(matched.reproducible ~= true, "reproducible output mismatch")
			table.insert(
				differences,
				Canonical.Object({ target = assert(matched.name), reason = "non-reproducible output checksums differ" })
			)
		end
	end

	return differences
end

return Verification
