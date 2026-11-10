-- ci/github/authentication/authentication.luau
--!strict

local Json = require("@formats/json")
local Fs = require("@std/fs")
local Net = require("@lute/net/client")
local Process = require("@lute/process")
local System = require("@lute/system")
local Configuration = require("@ci/github/configuration")
local Credentials = require("@ci/github/authentication/credentials")
local TokenPermissions = require("@ci/github/authentication/tokenPermissions")

local Authentication = {}
export type Access = { token: string, temporary: boolean, inspection: TokenPermissions.Inspection? }
const BASE64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

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
	local signaturePath = `{temporaryDirectory}/signature.bin`
	local ok, signature = xpcall(function(): Process.ProcessResult
		Fs.writeStringToFile(messagePath, message)
		Fs.writeStringToFile(keyPath, key)
		-- The process API captures stdout as text. Encode the binary signature before reading it.
		local signed = Process.run({ "openssl", "dgst", "-sha256", "-sign", keyPath, "-out", signaturePath, messagePath })
		if not signed.ok then
			return signed
		end
		return Process.run({ "openssl", "base64", "-A", "-in", signaturePath })
	end, tostring)
	Fs.removeDirectory(temporaryDirectory, { recursive = true })
	if not ok or not signature.ok then
		error("Unable to sign GitHub App authentication request", 0)
	end
	local encodedSignature = signature.stdout:gsub("%s", ""):gsub("%+", "-"):gsub("/", "_"):gsub("=+$", "")
	if encodedSignature == "" or not encodedSignature:match("^[%w_-]+$") then
		error("Unable to sign GitHub App authentication request", 0)
	end
	local jwt = message .. "." .. encodedSignature
	mask(jwt)
	local installationPath = if organization
		then `/orgs/{organization}/installation`
		else `/repos/{repository}/installation`
	local installation = request(jwt, "GET", installationPath)
	if not installation.ok then
		if installation.status == 401 then
			local decodedOk, body = pcall(Json.decode, installation.body)
			if decodedOk and type(body) == "table" then
				if body.message == "A JSON web token could not be decoded" then
					error("GitHub could not decode the App JWT", 0)
				elseif body.message == "'Issued at' claim ('iat') must be an Integer representing the time that the assertion was issued" then
					error("GitHub rejected the App JWT issue time", 0)
				elseif body.message == "Invalid issuer (iss) claim" then
					error("GitHub rejected the App JWT issuer", 0)
				elseif body.message == "JWT signature could not be verified" then
					error("GitHub could not verify the App JWT signature", 0)
				end
			end
		end
		error(`GitHub App installation lookup returned HTTP {installation.status}`, 0)
	end
	local decoded: unknown = Json.decode(installation.body)
	if type(decoded) ~= "table" or type(decoded.id) ~= "number" then
		error("GitHub returned an invalid App installation ID", 0)
	end
	local repositoryName = repository:match("/([^/]+)$")
	local created = request(jwt, "POST", `/app/installations/{decoded.id}/access_tokens`, {
		repositories = if organization then nil else { repositoryName },
		permissions = permissions,
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

local function appFailureReason(failure: unknown): string
	if type(failure) ~= "string" then
		return "unexpected App authentication error"
	end

	local lookupStatus = failure:match("^GitHub App installation lookup returned HTTP (%d%d%d)$")
	if lookupStatus then
		return `installation lookup returned HTTP {lookupStatus}`
	end

	local tokenStatus = failure:match("^App installation token request returned HTTP (%d%d%d)$")
	if tokenStatus then
		return `installation token request returned HTTP {tokenStatus}`
	end

	if failure == "Unable to sign GitHub App authentication request" then
		return "JWT signing failed"
	end
	if failure == "GitHub could not decode the App JWT"
		or failure == "GitHub rejected the App JWT issue time"
		or failure == "GitHub rejected the App JWT issuer"
		or failure == "GitHub could not verify the App JWT signature"
	then
		return failure
	end

	return "unexpected App authentication error"
end

function Authentication.Acquire(
	configuration: Configuration.Configuration,
	credentials: Credentials.Credentials,
	repository: string,
	roles: { string }?
): Access?
	local id = credentials:Get(configuration, "app_id")
	local key = credentials:Get(configuration, "app_private_key", true)

	if id and key then
		local ok, access = xpcall(appAccess, tostring, id, key, repository, configuration.roles.bootstrap_token.permissions.repository)
		if ok then
			print("::notice::Using a repository-scoped GitHub App installation token for branch bootstrap")
			return access
		end
		print(
			`::warning::App authentication failed: {appFailureReason(access)}. Check the configured App ID and private key, repository installation, and Contents/Workflows write permissions.`
		)
	end

	local token = credentials:Get(configuration, "bootstrap_token", true)
	local name = configuration.credentials.bootstrap_token

	if token and name and name:upper() ~= "GITHUB_TOKEN" then
		mask(token)
		local scopes = TokenPermissions.Required(configuration, roles or { "bootstrap_token" }, "bootstrap_token")
		local inspection: TokenPermissions.Inspection = if credentials.selected and credentials.selected.bootstrap_token == token
			then { state = "verified", required = scopes, missing = {} }
			else TokenPermissions.Inspect(token, scopes)
		if inspection.state ~= "verified" then
			TokenPermissions.Warn(configuration, "bootstrap_token", inspection)
		end
		if inspection.state == "invalid" or inspection.state == "insufficient" then
			return nil
		end
		print(
			`::notice::Using credential for bootstrap_token; scope audit: {inspection.state}. GitHub still enforces repository access on push.`
		)
		return { token = token, temporary = false, inspection = inspection }
	end

	credentials:WarnUnavailable(configuration, "source-ci", "Bootstrap delegation", { "app_id", "app_private_key", "bootstrap_token" })
	local idName = configuration.credentials.app_id or "<configure credentials.json roles.app_id>"
	local keyName = configuration.credentials.app_private_key or "<configure credentials.json roles.app_private_key>"
	local tokenName = name or "<configure credentials.json roles.bootstrap_token>"
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
