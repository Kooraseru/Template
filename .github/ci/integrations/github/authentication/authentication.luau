-- .github/ci/integrations/github/authentication/authentication.luau
--!strict

local Json = require("@formats/json")
local Fs = require("@std/fs")
local Net = require("@lute/net/client")
local Process = require("@lute/process")
local System = require("@lute/system")
local Configuration = require("@ci/integrations/github/configuration")
local Credentials = require("@ci/integrations/github/authentication/credentials")
local TokenPermissions = require("@ci/integrations/github/authentication/tokenPermissions")

local Authentication = {}
export type Access = { token: string, temporary: boolean, inspection: TokenPermissions.Inspection? }
local BASE64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local function mask(value: string): ()
	if Process.env.GITHUB_ACTIONS ~= "true" then
		return
	end
	local escaped = value:gsub("%%", "%%25"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
	print("::add-mask::" .. escaped)
end

local function base64url(value: string): string
	local encoded = table.create(math.ceil(#value / 3) * 4)
	for index = 1, #value, 3 do
		local first = string.byte(value, index)
		local second = string.byte(value, index + 1) or 0
		local third = string.byte(value, index + 2) or 0
		table.insert(encoded, BASE64URL:sub(math.floor(first / 4) + 1, math.floor(first / 4) + 1))
		local secondIndex = (first % 4) * 16 + math.floor(second / 16) + 1
		table.insert(encoded, BASE64URL:sub(secondIndex, secondIndex))
		if index + 1 <= #value then
			local thirdIndex = (second % 16) * 4 + math.floor(third / 64) + 1
			table.insert(encoded, BASE64URL:sub(thirdIndex, thirdIndex))
		end
		if index + 2 <= #value then
			local fourthIndex = third % 64 + 1
			table.insert(encoded, BASE64URL:sub(fourthIndex, fourthIndex))
		end
	end
	return table.concat(encoded)
end

local function request(token: string, method: string, path: string, body: unknown?): Net.Response
	return Net.request((Process.env.GITHUB_API_URL or "https://api.github.com") .. path, {
		method = method,
		headers = {
			Authorization = "Bearer " .. token,
			Accept = "application/vnd.github+json",
			["Content-Type"] = "application/json",
			["User-Agent"] = "Luau-CI-bootstrap",
		},
		body = if body ~= nil then Json.encode(body) else nil,
	})
end

local function appAccess(
	id: string,
	key: string,
	repository: string,
	permissions: { [string]: string }?,
	organization: string?
): Access
	if string.lower(System.os) ~= "linux" then
		error("GitHub App signing currently requires the Linux Actions runner", 0)
	end
	local now = math.floor(os.time())
	local message = base64url(Json.encode({ alg = "RS256", typ = "JWT" }))
		.. "."
		.. base64url(Json.encode({ iat = now - 60, exp = now + 540, iss = id }))
	local temporaryDirectoryResult = Process.run({ "mktemp", "-d", "-p", System.tmpdir(), "ci-app-signing.XXXXXXXX" })
	if not temporaryDirectoryResult.ok then
		error("Unable to create a private temporary directory for App authentication", 0)
	end
	local temporaryDirectory = temporaryDirectoryResult.stdout:gsub("%s+$", "")
	local messagePath = `{temporaryDirectory}/message.jwt`
	local keyPath = `{temporaryDirectory}/private-key.pem`
	local ok, signature = xpcall(function(): Process.ProcessResult
		Fs.writeStringToFile(messagePath, message)
		Fs.writeStringToFile(keyPath, key)
		return Process.run({ "openssl", "dgst", "-sha256", "-sign", keyPath, messagePath })
	end, tostring)
	Fs.removeDirectory(temporaryDirectory, { recursive = true })
	if not ok or not signature.ok then
		error("Unable to sign GitHub App authentication request", 0)
	end
	local jwt = message .. "." .. base64url(signature.stdout)
	mask(jwt)
	local installationPath = if organization
		then `/orgs/{organization}/installation`
		else `/repos/{repository}/installation`
	local installation = request(jwt, "GET", installationPath)
	if not installation.ok then
		error(`GitHub App installation lookup returned HTTP {installation.status}`, 0)
	end
	local decoded: unknown = Json.decode(installation.body)
	if type(decoded) ~= "table" or type(decoded.id) ~= "number" then
		error("GitHub returned an invalid App installation ID", 0)
	end
	local repositoryName = repository:match("/([^/]+)$")
	local created = request(jwt, "POST", `/app/installations/{decoded.id}/access_tokens`, {
		repositories = if organization then nil else { repositoryName },
		permissions = permissions or { contents = "write", workflows = "write" },
	})
	if not created.ok then
		error(`App installation token request returned HTTP {created.status}`, 0)
	end
	local token: unknown = Json.decode(created.body)
	if type(token) ~= "table" or type(token.token) ~= "string" or token.token == "" then
		error("GitHub returned an invalid App installation token", 0)
	end
	mask(token.token)
	return { token = token.token, temporary = true }
end

Authentication.AppAccess = appAccess

function Authentication.Acquire(
	configuration: Configuration.Configuration,
	credentials: Credentials.Credentials,
	repository: string,
	roles: { string }?
): Access?
	local id = credentials:Get(configuration, "app_id")
	local key = credentials:Get(configuration, "app_private_key", true)
	if id and key then
		local ok, access = xpcall(appAccess, tostring, id, key, repository)
		if ok then
			print("::notice::Using a repository-scoped GitHub App installation token for branch bootstrap")
			return access
		end
		-- Do not print errors that could contain credential material from a library.
		print(
			"::warning::App authentication failed. Check the configured app_id and app_private_key, repository installation, and Contents/Workflows write permissions."
		)
	end
	local token = credentials:Get(configuration, "bootstrap_token", true)
	local name = configuration.credentials.bootstrap_token
	if token and name and name:upper() ~= "GITHUB_TOKEN" then
		mask(token)
		local scopes = TokenPermissions.Required(configuration, roles or { "bootstrap_token" }, "bootstrap_token")
		local inspection = TokenPermissions.Inspect(token, scopes)
		if inspection.state ~= "verified" then
			TokenPermissions.Warn(configuration, "bootstrap_token", inspection)
		end
		if inspection.state == "invalid" or inspection.state == "insufficient" then
			return nil
		end
		print(
			`::notice::Using configured bootstrap_token secret {name}; scope audit: {inspection.state}. GitHub still enforces repository access on push.`
		)
		return { token = token, temporary = false, inspection = inspection }
	end
	local idName = configuration.credentials.app_id or "<configure github.credentials.app_id>"
	local keyName = configuration.credentials.app_private_key or "<configure github.credentials.app_private_key>"
	local tokenName = name or "<configure github.credentials.bootstrap_token>"
	print(
		`::notice::Native job graph unavailable. Configure GitHub App variable/secret {idName} and private-key secret {keyName}, or bootstrap-token secret {tokenName}. Continuing with the Luau scheduler.`
	)
	return nil
end

function Authentication.Release(access: Access): ()
	if not access.temporary then
		return
	end
	local ok, response = xpcall(request, tostring, access.token, "DELETE", "/installation/token", nil)
	if not ok or not response.ok then
		print("::warning::Could not revoke the temporary App token; GitHub will expire it automatically")
	end
end

return Authentication
