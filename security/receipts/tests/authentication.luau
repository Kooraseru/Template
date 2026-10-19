-- security/receipts/tests/authentication.luau
--!strict

local AuthenticationTests = {}

--# Modules

local Fs = require("@lune/fs")
local Datetime = require("@lune/datetime")
local Canonical = require("../../../libraries/bootstrap/canonical")
local Json = require("../../../libraries/bootstrap/json")
local Bytes = require("../../../libraries/bootstrap/bytes")
local Native = require("../../../libraries/bootstrap/native")
local Verification = require("../verification")
local Authentication = require("../authentication")

--# Helpers

local function patch(value: Canonical.Value, selected: Canonical.Value?): Canonical.Object
	local result = Json.Object(value)

	if selected then
		for key, field in Json.Fields(selected) do
			result = Json.Replace(result, key, field)
		end
	end

	return result
end

--# Functions

function AuthenticationTests.Run()
	local document = Json.Fields(Canonical.Decode(Fs.readFile("security/receipts/ruleset.json")))
	local cases = Json.Fields(document.cases)
	local keys = Json.Fields(cases.test_key)
	local now = Datetime.now().unixTimestampMillis

	local function fixture(): Canonical.Object
		return Json.Replace(assert(cases.fixture), "created_at", Datetime.fromUnixTimestamp(now / 1000):toIsoDate())
	end

	for _, raw in Json.Array(cases.authentication) do
		local scenario = Json.Fields(raw)
		local receipt = fixture()

		for _, name in { "diagnostic", "source_authorization" } do
			if scenario[name] then
				receipt = Json.Replace(receipt, name, scenario[name])
			end
		end

		if scenario.age_days then
			receipt = Json.Replace(
				receipt,
				"created_at",
				Datetime.fromUnixTimestamp(now / 1000 - Json.Number(scenario.age_days) * 86400):toIsoDate()
			)
		end

		local success, envelope = pcall(function(): Canonical.Object
			if Json.String(scenario.kind) == "signature" then
				return Authentication.Sign(receipt, "admin-key", Json.String(keys.private_key), now)
			end

			return Canonical.Object({
				receipt = receipt,
				authentication = Canonical.Object({
					kind = assert(scenario.kind),
					run_id = "123",
					controller_sha = string.rep("e", 40),
					bootstrap = scenario.bootstrap or false,
				}),
			})
		end)

		if not success then
			assert(scenario.valid == false, "valid receipt failed signing: " .. Json.String(scenario.name))
			continue
		end

		if scenario.tamper == true then
			envelope = Json.Replace(envelope, "receipt", Json.Replace(receipt, "tested_sha", string.rep("f", 40)))
		end

		local run = patch(assert(cases.hosted_run), scenario.run_patch)
		local enrollment = Canonical.Object({
			id = "admin-key",
			algorithm = "ed25519",
			public_key = assert(keys.public_key),
			login = "admin",
			revoked = scenario.revoked or false,
		})
		local repository = scenario.repository
		local context: Authentication.Context = {
			Repository = if repository then Json.String(repository) else "owner/project",
			Keys = Canonical.Object({ keys = Canonical.Array(if scenario.unknown == true then {} else { enrollment }) }),
			IsAdmin = function(_login: string): boolean
				return scenario.admin ~= false
			end,
			HostedRun = function(_id: Canonical.Value): Canonical.Value
				return run
			end,
			AllowBootstrap = function(_envelope: Canonical.Value, _run: Canonical.Value): boolean
				return scenario.allow_bootstrap == true
			end,
			AllowDiagnostic = function(_receipt: Canonical.Value): boolean
				return scenario.allow_diagnostic == true
			end,
			AllowPendingRun = function(_run: Canonical.Value): boolean
				return scenario.allow_pending == true
			end,
		}
		local accepted, result = pcall(Authentication.Authenticate, envelope, context, now)
		assert(
			accepted == scenario.valid,
			"receipt authentication case: " .. Json.String(scenario.name) .. ": " .. tostring(result)
		)

		if accepted then
			assert(result.validator == "admin", "unexpected receipt validator")
		end
	end

	for _, raw in Json.Array(cases.reuse) do
		local scenario = Json.Fields(raw)
		local target = Json.Array(Json.Fields(fixture()).targets)[1]

		if scenario.tree_mode == true then
			target = Json.Replace(target, "reuse_identity", "source_tree")
		end

		assert(
			Verification.Applicable(target, patch(target, scenario.patch)) == scenario.valid,
			"receipt reuse case: " .. Json.String(scenario.name)
		)
	end

	for _, raw in Json.Array(cases.execution) do
		local scenario = Json.Fields(raw)
		local target = Canonical.Object({ execution = assert(scenario.execution) })
		assert(
			Verification.ExecutionValid(target, raw) == scenario.valid,
			"execution coverage case: " .. Json.String(scenario.name)
		)
	end

	for _, raw in Json.Array(cases.comparison) do
		local scenario = Json.Fields(raw)
		local accepted, claim = fixture(), fixture()
		local target = Json.Array(Json.Fields(claim).targets)[1]

		if scenario.changed_files == true then
			local files = table.clone(Json.Array(Json.Fields(target).files))
			files[1] = Json.Replace(files[1], "sha256", string.rep("0", 64))
			target = Json.Replace(target, "files", Canonical.Array(files))
		end

		if scenario.failed_target == true then
			target = Json.Replace(target, "result", "failure")
		end

		claim =
			Json.Replace(claim, "targets", Canonical.Array(if scenario.missing_target == true then {} else { target }))

		if scenario.base_changed == true then
			claim =
				Json.Replace(claim, "pr", Json.Replace(assert(Json.Fields(claim).pr), "base_sha", string.rep("f", 40)))
		end

		if scenario.reproducible == true then
			local original = Json.Array(Json.Fields(accepted).targets)[1]
			accepted =
				Json.Replace(accepted, "targets", Canonical.Array({ Json.Replace(original, "reproducible", true) }))
		end

		local success, differences = pcall(Verification.Compare, claim, accepted, now)
		assert(success == scenario.valid, "receipt comparison case: " .. Json.String(scenario.name))

		if success then
			assert(#differences == Json.Number(scenario.differences), "unexpected comparison differences")
		end
	end

	local vectors =
		Json.Fields(Json.Fields(Canonical.Decode(Fs.readFile("libraries/bootstrap/ruleset.json"))).authentication)

	for _, raw in Json.Array(vectors.vectors) do
		local vector = Json.Fields(raw)
		local message = Bytes.FromHex(Json.String(vector.message_utf8_hex))
		local signature = Native.Sign(message, Json.String(vector.private_pkcs8_der_hex), true)
		assert(Bytes.Hex(signature) == Json.String(vector.signature_hex), "Ed25519 signature byte mismatch")
		assert(
			Native.Verify(message, signature, Json.String(vector.public_spki_der_hex), true),
			"Ed25519 golden signature rejected"
		)
		assert(
			not Native.Verify(message .. "\n", signature, Json.String(vector.public_spki_der_hex), true),
			"modified signed bytes accepted"
		)
		assert(
			not Native.Verify(message, signature:sub(1, -2), Json.String(vector.public_spki_der_hex), true),
			"truncated signature accepted"
		)
	end
end

return AuthenticationTests
