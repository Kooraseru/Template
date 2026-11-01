-- repo/ci/bootstrap/skipPolicy.luau
--!strict

local Fs = require("@lune/fs")
local Net = require("@lune/net")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Authentication = require("@ci/github/authentication")
local Configuration = require("@ci/github/configuration")
local Credentials = require("@ci/github/credentials")
local Contract = require("./contract")
local SetupInstructions = require("@ci/github/setupInstructions")
local Responses = require("@ci/github/responses")

local SkipPolicy = {}

local function record(value: unknown): { [string]: unknown }
	if type(value) ~= "table" then
		error("CI execution settings must be TOML tables", 0)
	end
	local result: { [string]: unknown } = {}
	for key, item in value do
		if type(key) ~= "string" then
			error("CI execution setting names must be strings", 0)
		end
		result[key] = item
	end
	return result
end

local function neutralCheckPermissions(): { [string]: string }
	local path = "repo/config/ci/authorization/check-runs.toml"
	local decoded = record(Serde.decode("toml", Fs.readFile(path)))
	for field in decoded do
		if field ~= "app" then
			error(`{path}: unknown authorization section {tostring(field)}`, 0)
		end
	end
	local app = record(decoded.app)
	for field in app do
		if field ~= "repository" then
			error(`{path}: unknown App permission scope {tostring(field)}`, 0)
		end
	end
	local repository = record(app.repository)
	local permissions: { [string]: string } = {}
	for name, value in repository do
		if not name:match("^[a-z_]+$") or (value ~= "read" and value ~= "write") then
			error(`{path}: invalid repository permission declaration`, 0)
		end
		permissions[name] = value :: string
	end
	if permissions.checks ~= "write" then
		error(`{path}: neutral runtime skips require app.repository.checks = "write"`, 0)
	end
	return permissions
end

function SkipPolicy.Conclusion(identity: string): string
	local decoded = record(Serde.decode("toml", Fs.readFile("repo/config/ci/execution.toml")))
	for field in decoded do
		if field ~= "skip" then
			error(`Unknown CI execution setting {tostring(field)}`, 0)
		end
	end
	local settings = record(decoded.skip)
	for field in settings do
		if field ~= "default" and field ~= "components" then
			error(`Unknown CI skip setting {tostring(field)}`, 0)
		end
	end
	local supported = { success = true, failure = true, neutral = true }
	if type(settings.default) ~= "string" or not supported[settings.default] then
		error("skip.default must be success, failure, or neutral", 0)
	end
	local overrides = record(settings.components)
	for name, value in overrides do
		if type(name) ~= "string" or not Contract.ValidIdentity(name) then
			error("Invalid skip component identity", 0)
		end
		if type(value) ~= "string" or not supported[value] then
			error(`skip.components.{name} must be success, failure, or neutral`, 0)
		end
	end
	local conclusion = overrides[identity]
	if type(conclusion) ~= "string" then
		conclusion = settings.default
	end
	return conclusion :: string
end

local function warnAuthorization(identity: string, status: string, appState: string?): ()
	local configuration = Configuration.new()
	local permissions: { string } = {}
	for name, access in neutralCheckPermissions() do
		table.insert(permissions, `- {name}: {access}`)
	end
	table.sort(permissions)
	local values = SetupInstructions.Values(
		configuration,
		configuration.credentials.bootstrap_token or "CI_TOKEN",
		{},
		neutralCheckPermissions()
	)
	values.component = identity
	values.status = status
	values.app_state = appState or "unavailable"
	values.app_permissions = table.concat(permissions, "\n")
	SetupInstructions.Guides(values)
	print(
		`::warning::Neutral Check Run authorization for {identity}: {status}. Verify App {values.app_id}/{values.app_private_key} and its declared permissions; see the job summary.`
	)
	local text = Responses.Template("authorization.check-runs"):gsub("{{([%w_]+)}}", function(key)
		return values[key] or error(`Unknown Check Run authorization template field {key}`, 0)
	end)
	Responses.Record("authorization/check-runs", text)
end

function SkipPolicy.ReportNeutral(identity: string, credentials: Credentials.Credentials?): ()
	if not credentials then
		warnAuthorization(identity, "supported reporting credential unavailable", "unavailable")
		error(
			"Current credential method cannot report neutral: this backend requires GitHub App credentials; a classic PAT does not support Check Run creation",
			0
		)
	end
	local configuration = Configuration.new()
	local appId = credentials:Get(configuration, "app_id")
	local privateKey = credentials:Get(configuration, "app_private_key", true)
	if not appId or not privateKey then
		warnAuthorization(
			identity,
			"supported reporting credential unavailable",
			if appId or privateKey then "partial" else "unavailable"
		)
		error(
			`Current credential method cannot report neutral for {identity}: a classic PAT cannot create Check Runs; configure an App installed on the owning personal account or organization with Checks: write`,
			0
		)
	end
	local repository = configuration:ResolveRepository(configuration.repository)
	local sha = Process.env.CI_SOURCE_SHA or Process.env.GITHUB_SHA
	if not sha or #sha ~= 40 or not sha:match("^%x+$") then
		error("A neutral Check Run requires the source commit SHA", 0)
	end
	local acquired, access = pcall(function(): Authentication.Access
		return Authentication.AppAccess(appId, privateKey, repository, neutralCheckPermissions())
	end)
	if not acquired then
		warnAuthorization(identity, "App authentication or installation access rejected", "configured")
		error(`Could not authorize neutral Check Run reporting for {identity}`, 0)
	end
	local api = Process.env.GITHUB_API_URL or "https://api.github.com"
	local run = Process.env.GITHUB_RUN_ID or "local"
	local response = Net.request({
		url = `{api}/repos/{repository}/check-runs`,
		method = "POST",
		headers = {
			Authorization = `Bearer {access.token}`,
			Accept = "application/vnd.github+json",
			["Content-Type"] = "application/json",
			["X-GitHub-Api-Version"] = "2022-11-28",
			["User-Agent"] = "Luau-CI-bootstrap",
		},
		body = Serde.encode("json", {
			name = `CI skip: {identity}`,
			head_sha = sha,
			status = "completed",
			conclusion = "neutral",
			external_id = `{run}:{identity}`,
			output = {
				title = `Skipped: {identity}`,
				summary = `Component outcome: skipped. Configured Check Run conclusion: neutral.`,
			},
		}),
	})
	Authentication.Release(access)
	if not response.ok then
		if response.statusCode == 401 or response.statusCode == 403 or response.statusCode == 404 then
			warnAuthorization(identity, `Check Run access rejected (HTTP {response.statusCode})`, "configured")
		end
		error(
			`Could not create neutral Check Run for {identity} (HTTP {response.statusCode}); verify App installation and Checks: write permission`,
			0
		)
	end
end

return SkipPolicy
