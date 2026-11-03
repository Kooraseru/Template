-- repo/ci/components/rulesets/sync/init.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Authentication = require("@ci/github/authentication/authentication")
local Configuration = require("@ci/github/configuration")
local RulesetCatalog = require("@ci/github/rulesets/rulesetCatalog")
local RulesetSync = require("@ci/github/rulesets/rulesetSync")
local TokenPermissions = require("@ci/github/authentication/tokenPermissions")
local Responses = require("@ci/github/reporting/responses")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

local function report(configuration: Configuration.Configuration, state: string, diagnostic: string, selectedColor: string): ()
	local markdown = Responses.Fill(Responses.Template("rulesets.authorization"), {
		state = state,
		diagnostic = diagnostic,
		token_name = configuration.credentials.rulesets_token or "<github.credentials.rulesets_token>",
	})
	Responses.Record("authorization/rulesets", markdown, selectedColor)
end

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	local configuration = Configuration.new()
	local repository = configuration:ResolveRepository(configuration.repository)
	local definitions = RulesetCatalog.Read()
	local appId = Process.env.CI_CREDENTIAL_APP_ID
	local privateKey = Process.env.CI_CREDENTIAL_APP_PRIVATE_KEY
	local token = Process.env.CI_CREDENTIAL_RULESETS_TOKEN
	Process.env.CI_CREDENTIAL_APP_ID = nil
	Process.env.CI_CREDENTIAL_APP_PRIVATE_KEY = nil
	Process.env.CI_CREDENTIAL_RULESETS_TOKEN = nil
	local access: Authentication.Access? = nil

	-- Administration: write is not part of the ordinary read-only or publication GITHUB_TOKEN.
	if appId and appId ~= "" and privateKey and privateKey ~= "" then
		local ok, result = pcall(Authentication.AppAccess, appId, privateKey, repository, { administration = "write" })
		if ok then
			access = result
		else
			print("::warning::GitHub App could not obtain repository Administration: write for rulesets")
		end
	end
	if not access and token and token ~= "" and token ~= Process.env.GH_TOKEN then
		local required = TokenPermissions.Required(configuration, { "rulesets_token" }, "rulesets_token")
		local inspection = TokenPermissions.Inspect(token, required)
		if inspection.state ~= "invalid" and inspection.state ~= "insufficient" then
			access = { token = token, temporary = false, inspection = inspection }
		end
	end
	if not access then
		local secret = configuration.credentials.rulesets_token or "<github.credentials.rulesets_token>"
		local problem = `No App or {secret} credential with repository Administration: write was available.`
		print(`::warning::Rulesets sync skipped: {problem} PR validation remains available.`)
		report(configuration, "Skipped: authorization unavailable", problem, "warning")
		return "skipped"
	end
	local ok, receipts, changed = pcall(RulesetSync.Sync, repository, access.token, definitions)
	Authentication.Release(access)
	if not ok then
		-- Rejected API changes must remain failures and include a reviewable permissions record.
		local problem = tostring(receipts)
		report(configuration, "Failed: GitHub rejected the ruleset operation", problem, "failure")
		error(problem, 0)
	end
	Fs.writeDir("build/github/ruleset-sync")
	Fs.writeFile(
		"build/github/ruleset-sync/index.json",
		Serde.encode("json", { applied = true, rulesets = receipts })
	)
	if not changed then
		print("All managed GitHub rulesets already match their source definitions")
	end
	return nil
end

return Component
