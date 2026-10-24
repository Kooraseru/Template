-- ci/publication/releases/protection.luau
--!strict

local Protection = {}

--# Modules

local D = require("../../utilities/documents")
local C = require("../../utilities/canonical")
local Json = require("../../utilities/json")
local Process = require("@lune/process")
local Datetime = require("@lune/datetime")
local Client = require("./client")

--# Helpers

local function references(value: C.Value): boolean
	for _, raw in Json.Array(value) do
		if table.find({ "refs/heads/source", "~DEFAULT_BRANCH", "~ALL" }, Json.String(raw)) then
			return true
		end
	end
	return false
end

local function adminOnly(actors: { C.Value }): boolean
	for _, actor in actors do
		if
			D.Text(actor, "actor_type") ~= "RepositoryRole"
			or D.Number(actor, "actor_id") ~= 5
			or not table.find({ "pull_request", "always" }, D.Text(actor, "bypass_mode"))
		then
			return false
		end
	end
	return true
end

local function valid(rulesets: { C.Value }): boolean
	local checks, restricted = false, false
	for _, set in rulesets do
		if D.Get(set, "enforcement") ~= "active" or D.Get(set, "target") ~= "branch" then
			continue
		end
		local refs = D.Required(D.Required(set, "conditions"), "ref_name")
		if not references(D.Required(refs, "include")) or references(D.Get(refs, "exclude") or C.Array({})) then
			continue
		end
		local actors = D.Items(set, "bypass_actors")
		local kinds: { [string]: boolean } = {}
		local gate = false
		for _, rule in D.Items(set, "rules") do
			local kind = D.Text(rule, "type")
			kinds[kind] = true
			if kind == "required_status_checks" then
				local parameters = D.Required(rule, "parameters")
				if D.Get(parameters, "strict_required_status_checks_policy") == true then
					for _, check in D.Items(parameters, "required_status_checks") do
						gate = gate or (D.Get(check, "context") == "gate" and D.Get(check, "integration_id") == 15368)
					end
				end
			end
		end
		checks = checks
			or (
				adminOnly(actors)
				and kinds.pull_request == true
				and kinds.non_fast_forward == true
				and kinds.deletion == true
				and gate
			)
		restricted = restricted or (kinds.update == true and #actors == 1 and adminOnly(actors))
	end
	return checks and restricted
end

local function visible(value: C.Value): C.Value
	local fields: { [string]: C.Value } = {}
	for _, key in { "id", "name", "target", "source_type", "source", "enforcement", "conditions", "rules" } do
		fields[key] = D.Get(value, key) or C.Missing
	end
	fields.updated_at = Datetime.fromRfc3339(D.Text(value, "updated_at")).unixTimestampMillis
	return C.Object(fields)
end

--# Functions

function Protection.Valid(rulesets: { C.Value }): boolean
	local ok, accepted = pcall(valid, rulesets)
	return ok and accepted
end

function Protection.Verified(live: { C.Value }, attestation: C.Value?, repository: string): { C.Value }
	local complete = true
	for _, set in live do
		local field = D.Get(set, "bypass_actors")
		complete = complete and type(field) == "table" and field.kind == "array"
	end
	if complete then
		return live
	end
	assert(
		attestation and D.Get(attestation, "schema") == nil and D.Get(attestation, "repository") == repository,
		"admin source-protection attestation required"
	)
	local enrolled = D.Items(attestation, "rulesets")
	assert(#enrolled == #live and Protection.Valid(enrolled), "invalid source-protection attestation")
	local result: { C.Value } = {}
	for _, set in live do
		local match: C.Value? = nil
		for _, candidate in enrolled do
			if D.Equal(D.Get(candidate, "id"), D.Get(set, "id")) then
				match = candidate
				break
			end
		end
		assert(match and D.Equal(visible(match), visible(set)), "source protection changed; refresh admin attestation")
		table.insert(result, D.Set(set, "bypass_actors", D.Required(match, "bypass_actors")))
	end
	return result
end

function Protection.Require(repository: string, supplied: Client.API?)
	local api = supplied or Client.new(repository)
	local live: { C.Value } = {}
	for _, summary in api.Pages("/rulesets") do
		table.insert(live, (assert(api.Request("/rulesets/" .. D.Number(summary, "id")), "missing ruleset")))
	end
	local snapshot = Process.env.CI_SOURCE_PROTECTION
	local attestation = if snapshot and snapshot ~= "" then C.Decode(snapshot) else nil
	assert(
		Protection.Valid(Protection.Verified(live, attestation, repository)),
		"official publication requires source PR/check protections and administrator-only updates"
	)
end

function Protection.Run()
	Protection.Require(assert(Process.env.GITHUB_REPOSITORY))
end

return Protection
