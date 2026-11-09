-- .github/ci/integrations/github/authentication/tokenPermissions.luau
--!strict

local Fs = require("@std/fs")
local Toml = require("@formats/toml")
local Net = require("@lute/net/client")
local Process = require("@lute/process")
local Glob = require("@ci/bootstrap/discovery/glob")
local Configuration = require("@ci/integrations/github/configuration")
local Publication = require("@ci/integrations/github/publication")
local SetupInstructions = require("@ci/integrations/github/authentication/setupInstructions")
local Responses = require("@ci/integrations/github/reporting/responses")

local TokenPermissions = {}
export type Inspection = {
	state: "verified" | "insufficient" | "invalid" | "unverified",
	required: { string },
	granted: { string }?,
	missing: { string },
}

-- Declarations contribute requirements only for requested roles sharing this secret.
function TokenPermissions.Required(
	configuration: Configuration.Configuration,
	roles: { string },
	role: string
): { string }
	local name = configuration.credentials[role]
	local requested: { [string]: boolean } = {}

	for _, selected in roles do
		local selectedName = configuration.credentials[selected]
		if name and selectedName and name:upper() == selectedName:upper() then
			requested[selected] = true
		end
	end

	local scopes: { [string]: boolean } = {}

	for _, path in Glob.Find(".github/automation/authorization/*.toml") do
		local root = Publication.Record(Toml.decode(Fs.readFileToString(path)))
		local declaration = root.credential

		if declaration == nil then
			if root.classic ~= nil then
				error(`{path}: classic scope declarations require credential.role`, 0)
			end
			continue
		end

		local owner = Publication.Text(Publication.Record(declaration).role)
		if not owner:match("^[a-z][a-z0-9_]*$") then
			error(`{path}: invalid credential.role`, 0)
		end
		if not requested[owner] then
			continue
		end
		local required = Publication.Record(root.classic).scopes
		if type(required) ~= "table" or #required == 0 then
			error(`{path}: classic.scopes must be a nonempty array`, 0)
		end

		for index, scope in required do
			if type(index) ~= "number" or type(scope) ~= "string" or not scope:match("^[%w_:]+$") then
				error(`{path}: invalid classic token scope`, 0)
			end
			scopes[scope] = true
		end
	end

	local result: { string } = {}
	for scope in scopes do
		table.insert(result, scope)
	end
	table.sort(result)
	return result
end

local function covers(granted: { [string]: boolean }, required: string): boolean
	if granted[required] then
		return true
	end
	local parent = required:match("^([^:]+):")
	if parent and granted[parent] then
		return true
	end
	local target = required:match("^read:(.+)$")
	if target and (granted["write:" .. target] or granted["admin:" .. target]) then
		return true
	end
	target = required:match("^write:(.+)$")
	return (target ~= nil and granted["admin:" .. target] == true)
		or (required == "public_repo" and granted.repo == true)
end

function TokenPermissions.Evaluate(status: number, headers: { [string]: string }, required: { string }): Inspection
	local result: Inspection = { state = "unverified", required = required, missing = {} }
	if status == 401 then
		result.state = "invalid"
		return result
	end
	if status < 200 or status >= 300 then
		return result
	end
	local inventory: string? = nil

	for key, value in headers do
		if key:lower() == "x-oauth-scopes" then
			inventory = if type(value) == "string" then value else table.concat(value, ",")
		end
	end

	if inventory == nil then
		return result
	end
	local granted: { [string]: boolean } = {}
	local ordered: { string } = {}

	for scope in inventory:gmatch("[%w_:]+") do
		if not granted[scope] then
			granted[scope] = true
			table.insert(ordered, scope)
		end
	end

	table.sort(ordered)
	result.granted = ordered

	for _, scope in required do
		if not covers(granted, scope) then
			table.insert(result.missing, scope)
		end
	end

	result.state = if #result.missing > 0 then "insufficient" else "verified"
	return result
end

function TokenPermissions.Inspect(token: string, required: { string }): Inspection
	local options: Net.Metadata = {
		headers = {
			Authorization = "Bearer " .. token,
			Accept = "application/vnd.github+json",
			["User-Agent"] = "Luau-CI",
		},
	}
	local ok, response = pcall(function(): Net.Response
		return Net.request((Process.env.GITHUB_API_URL or "https://api.github.com") .. "/user", options)
	end)
	if not ok then
		return { state = "unverified", required = required, missing = {} }
	end
	if token:match("^github_pat_") or token:match("^gh[su]_") then
		return TokenPermissions.Evaluate(response.status, {}, required)
	end
	return TokenPermissions.Evaluate(response.status, response.headers, required)
end

local function scopeText(scopes: { string }?): string
	if not scopes then
		return "Unknown."
	end
	return if #scopes > 0 then "`" .. table.concat(scopes, "`, `") .. "`" else "None."
end

function TokenPermissions.Evidence(inspection: Inspection?, rejected: boolean?): string
	local state = if rejected or not inspection then "rejected" else inspection.state
	local values = {
		observation = Responses.Template("token." .. state),
		granted = scopeText(if inspection then inspection.granted else nil),
		required = scopeText(if inspection then inspection.required else nil),
		missing = scopeText(if inspection and inspection.granted then inspection.missing else nil),
	}
	local text = Responses.Template("token.evidence"):gsub("{{([%w_]+)}}", function(key)
		return values[key] or error(`Unknown permission evidence field {key}`, 0)
	end)
	return text
end

function TokenPermissions.Warn(
	configuration: Configuration.Configuration,
	role: string,
	inspection: Inspection,
	rejected: boolean?
): ()
	local name = configuration.credentials[role] or role
	local values = SetupInstructions.Values(configuration, name, inspection.required)
	values.permission_evidence = TokenPermissions.Evidence(inspection, rejected)
	SetupInstructions.Guides(values)
	local outcome = if rejected then "operation rejected" else inspection.state
	print(
		`::warning::Credential {name}: {outcome}; scope audit: {inspection.state}. Verify permissions and resource access; see the job summary.`
	)
	local summary = Responses.Template("authorization.token"):gsub("{{([%w_]+)}}", function(key)
		return values[key] or error(`Unknown authorization template field {key}`, 0)
	end)
	Responses.Record("authorization/token", summary)
end

return TokenPermissions
