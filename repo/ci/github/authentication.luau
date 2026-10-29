-- repo/ci/github/authentication.luau
--!strict

local DateTime = require("@lune/datetime")
local Fs = require("@lune/fs")
local Net = require("@lune/net")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Configuration = require("./configuration")
local Credentials = require("./credentials")

local Authentication = {}
export type Access = { token: string, temporary: boolean }

local function mask(value: string): ()
	if Process.env.GITHUB_ACTIONS ~= "true" then
		return
	end
	local escaped = value:gsub("%%", "%%25"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
	print("::add-mask::" .. escaped)
end

local function base64url(value: string): string
	local encoded = Process.exec("openssl", { "base64", "-A" }, { stdio = { stdin = value } })
	if not encoded.ok then
		error("OpenSSL could not encode the App authentication request", 0)
	end
	local result = encoded.stdout:gsub("%+", "-"):gsub("/", "_"):gsub("=+$", "")
	return result
end

local function request(token: string, method: Net.HttpMethod, path: string, body: unknown?): Net.FetchResponse
	return Net.request({
		url = (Process.env.GITHUB_API_URL or "https://api.github.com") .. path,
		method = method,
		headers = {
			Authorization = "Bearer " .. token,
			Accept = "application/vnd.github+json",
			["Content-Type"] = "application/json",
			["User-Agent"] = "Luau-CI-bootstrap",
		},
		body = if body ~= nil then Serde.encode("json", body) else nil,
	})
end

local function appAccess(id: string, key: string, repository: string): Access
	if Process.os ~= "linux" then
		error("GitHub App signing currently requires the Linux Actions runner", 0)
	end
	local now = math.floor(DateTime.now().unixTimestamp)
	local message = base64url(Serde.encode("json", { alg = "RS256", typ = "JWT" }))
		.. "."
		.. base64url(Serde.encode("json", { iat = now - 60, exp = now + 540, iss = id }))
	Fs.writeDir("build/github")
	local messagePath = "build/github/app-request.jwt-message"
	Fs.writeFile(messagePath, message)
	-- Only the public JWT claims touch disk. The private key is passed on stdin.
	local ok, signature = xpcall(Process.exec, tostring, "openssl", {
		"dgst",
		"-sha256",
		"-sign",
		"/dev/stdin",
		messagePath,
	}, { stdio = { stdin = key } })
	Fs.removeFile(messagePath)
	if not ok or not signature.ok then
		error("Unable to sign GitHub App authentication request", 0)
	end
	local jwt = message .. "." .. base64url(signature.stdout)
	mask(jwt)
	local installation = request(jwt, "GET", `/repos/{repository}/installation`)
	if not installation.ok then
		error(`GitHub App installation lookup returned HTTP {installation.statusCode}`, 0)
	end
	local decoded: unknown = Serde.decode("json", installation.body)
	if type(decoded) ~= "table" or type(decoded.id) ~= "number" then
		error("GitHub returned an invalid App installation ID", 0)
	end
	local repositoryName = repository:match("/([^/]+)$")
	local created = request(jwt, "POST", `/app/installations/{decoded.id}/access_tokens`, {
		repositories = { repositoryName },
		permissions = { contents = "write", workflows = "write" },
	})
	if not created.ok then
		error(`App installation token request returned HTTP {created.statusCode}`, 0)
	end
	local token: unknown = Serde.decode("json", created.body)
	if type(token) ~= "table" or type(token.token) ~= "string" or token.token == "" then
		error("GitHub returned an invalid App installation token", 0)
	end
	mask(token.token)
	return { token = token.token, temporary = true }
end

function Authentication.Acquire(
	configuration: Configuration.Configuration,
	credentials: Credentials.Credentials,
	repository: string
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
		print(`::notice::Using configured bootstrap_token secret {name}; GitHub will verify its permissions on push`)
		return { token = token, temporary = false }
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
