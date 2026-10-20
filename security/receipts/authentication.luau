-- security/receipts/authentication.luau
--!strict

local Authentication = {}

--# Modules

local Canonical = require("../../libraries/bootstrap/canonical")
local Json = require("../../libraries/bootstrap/json")
local Native = require("../../libraries/bootstrap/native")
local Base64 = require("../../libraries/bootstrap/base64")
local Verification = require("./verification")

--# Types

export type Context = {
	Repository: string,
	Keys: Canonical.Value,
	IsAdmin: (string) -> boolean,
	HostedRun: ((Canonical.Value) -> Canonical.Value)?,
	AllowBootstrap: ((Canonical.Value, Canonical.Value) -> boolean)?,
	AllowPendingRun: ((Canonical.Value) -> boolean)?,
	AllowDiagnostic: ((Canonical.Value) -> boolean)?,
}

export type Accepted = { receipt: Canonical.Object, validator: string }

--# Helpers

local function stringField(value: Canonical.Value?, key: string): string?
	if not value or not Json.Truthy(value) then
		return nil
	end

	local field = Json.Fields(value)[key]

	if field == nil or (type(field) == "table" and (field.kind == "null" or field.kind == "missing")) then
		return nil
	end

	return Json.String(field)
end

--# Functions

function Authentication.Sign(
	rawReceipt: Canonical.Value,
	keyId: string,
	privateKey: string,
	now: number?
): Canonical.Object
	local receipt = Verification.Validate(rawReceipt, now)
	local bytes = assert(Canonical.Encode(receipt))
	local signature = Base64.Encode(Native.Sign(bytes, privateKey))

	return Canonical.Object({
		receipt = receipt,
		authentication = Canonical.Object({ kind = "signature", key_id = keyId, signature = signature }),
	})
end

function Authentication.Authenticate(rawEnvelope: Canonical.Value, context: Context, now: number?): Accepted
	local envelope = Json.Fields(rawEnvelope)
	local receipt = Verification.Validate(assert(envelope.receipt, "missing receipt"), now)
	local fields = Json.Fields(receipt)
	assert(
		not Json.Truthy(fields.diagnostic) or (context.AllowDiagnostic and context.AllowDiagnostic(receipt)),
		"diagnostic results cannot become accepted validation"
	)
	assert(Json.String(fields.repository):lower() == context.Repository:lower(), "wrong repository")
	local auth = Json.Fields(envelope.authentication)
	local kind = Json.String(auth.kind)
	assert(Json.Fields(context.Keys).schema == nil, "key enrollment contains unsupported schema field")

	if kind == "signature" then
		local selected: { [string]: Canonical.Value }? = nil

		for _, rawKey in Json.Array(Json.Fields(context.Keys).keys) do
			local key = Json.Fields(rawKey)

			if stringField(rawKey, "id") == Json.String(auth.key_id) and not Json.Truthy(key.revoked) then
				selected = key
				break
			end
		end

		assert(selected and Json.String(selected.algorithm) == "ed25519", "untrusted signing key")
		local login = Json.String(selected.login)
		assert(context.IsAdmin(login), "signer is not a repository administrator")
		local signature = Base64.Decode(Json.String(auth.signature))
		assert(
			Native.Verify(assert(Canonical.Encode(receipt)), signature, Json.String(selected.public_key)),
			"untrusted signature or validator"
		)

		return { receipt = receipt, validator = login }
	elseif kind == "hosted" and context.HostedRun then
		local rawRun = context.HostedRun(assert(auth.run_id, "missing hosted run ID"))
		local run = Json.Fields(rawRun)
		local actor = stringField(run.actor, "login")
		local bootstrap = auth.bootstrap == true
			and context.AllowBootstrap
			and context.AllowBootstrap(rawEnvelope, rawRun)
		local rawApproval = fields.source_authorization
		local approval: { [string]: Canonical.Value } = if rawApproval and Json.Truthy(rawApproval)
			then Json.Fields(rawApproval)
			else {}
		local rawKind = approval.kind
		local approvalKind = if rawKind then Json.String(rawKind) else ""
		local source = stringField(rawRun, "event") == "push"
			and (approvalKind == "admin-merge" or approvalKind == "admin-source-push")
			and stringField(fields.source_authorization, "actor") == actor
			and stringField(fields.source_authorization, "source_sha") == stringField(rawRun, "head_sha")
		assert(
			(source or stringField(rawRun, "event") == "workflow_dispatch")
				and (stringField(rawRun, "head_branch") == "source" or bootstrap)
				and stringField(rawRun, "head_sha") == Json.String(auth.controller_sha)
				and (stringField(rawRun, "conclusion") == "success" or (context.AllowPendingRun and context.AllowPendingRun(
					rawRun
				)))
				and (stringField(run.head_repository, "full_name") or ""):lower() == context.Repository:lower()
				and stringField(rawRun, "path") == ".github/workflows/ci.yml"
				and actor
				and context.IsAdmin(actor),
			"untrusted hosted validation"
		)

		return { receipt = receipt, validator = actor }
	end

	error("contributor claim is not accepted validation")
end

return Authentication
