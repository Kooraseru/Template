-- ci/github/publication/init.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local Net = require("@lute/net/client")
local Process = require("@lute/process")
local Configuration = require("@ci/github/configuration")

local Publication = {}

function Publication.Encode(value: string): string
	return (
		value:gsub("([^%w%-_%.~])", function(character: string): string
			return string.format("%%%02X", string.byte(character))
		end)
	)
end

function Publication.Output(name: string, value: string): ()
	local path = Process.env.GITHUB_OUTPUT
	if path then
		local current = if Fs.exists(path) and Fs.type(path) == "file" then Fs.readFileToString(path) else ""
		local separator = if current ~= "" and current:sub(-1) ~= "\n" then "\n" else ""
		Fs.writeStringToFile(path, `{current}{separator}{name}={value}\n`)
	end
end

function Publication.Record(value: unknown): { [string]: unknown }
	if type(value) ~= "table" then
		error("Expected a publication data object", 0)
	end
	local result: { [string]: unknown } = {}
	for key, item in value do
		if type(key) == "string" then
			result[key] = item
		end
	end
	return result
end

function Publication.Text(value: unknown): string
	if type(value) ~= "string" or value == "" then
		error("Expected a nonempty publication string", 0)
	end
	return value
end

local function response(method: "GET" | "POST" | "PATCH" | "PUT" | "DELETE", path: string, body: unknown?)
	local token = Process.env.GH_TOKEN
	if not token or token == "" then
		error("Publication requires the run-provided GITHUB_TOKEN with the declared write permissions", 0)
	end
	local origin = if Process.env.TEMPLATE_PUBLICATION_REHEARSAL == "1"
		then "http://127.0.0.1:47831" else "https://api.github.com"
	local response = Net.request(`{origin}/{path}`, {
		method = method,
		headers = {
			Authorization = `Bearer {token}`,
			Accept = "application/vnd.github+json",
			["Content-Type"] = "application/json",
			["X-GitHub-Api-Version"] = "2022-11-28",
			["User-Agent"] = "Template-CI",
		},
		body = if body ~= nil then Json.encode(body) else nil,
	})
	return response
end

local function responseMessage(body: string): string
	local token = Process.env.GH_TOKEN
	local safe = body:gsub("[%c]", " ")
	if token and token ~= "" then
		safe = safe:gsub(token, "[redacted]")
	end
	return safe:sub(1, 240)
end

function Publication.Request(
	method: "GET" | "POST" | "PATCH" | "PUT" | "DELETE",
	path: string,
	body: unknown?
): (number, { [string]: unknown })
	local result = response(method, path, body)
	if result.body == "" then
		return result.status, {}
	end

	local decodedOk, decoded = pcall(Json.decode, result.body)
	if decodedOk and type(decoded) == "table" then
		return result.status, Publication.Record(decoded)
	end
	if result.status < 200 or result.status >= 300 then
		return result.status, { message = responseMessage(result.body) }
	end
	error(
		`GitHub returned a non-JSON response for {method} {path} (HTTP {result.status}): {responseMessage(result.body)}`,
		0
	)
end

function Publication.List(path: string): { unknown }
	local result = response("GET", path, nil)
	Publication.RequireSuccess(result.status, "Read GitHub list", { message = responseMessage(result.body) })
	local value: unknown = Json.decode(result.body)
	if type(value) ~= "table" then
		error("Expected a GitHub asset list", 0)
	end
	local items: { unknown } = {}
	for _, item in value do
		table.insert(items, item)
	end
	return items
end

function Publication.Upload(repository: string, releaseId: number, name: string, bytes: string): { [string]: unknown }
	local token = Process.env.GH_TOKEN
	if not token or token == "" then
		error("Missing run-provided publication token", 0)
	end
	local uploadOrigin = if Process.env.TEMPLATE_PUBLICATION_REHEARSAL == "1"
		then "http://127.0.0.1:47831" else "https://uploads.github.com"
	local result = Net.request(`{uploadOrigin}/repos/{repository}/releases/{releaseId}/assets?name={Publication.Encode(name)}`, {
		method = "POST",
		headers = {
			Authorization = `Bearer {token}`,
			["Content-Type"] = "application/octet-stream",
			Accept = "application/vnd.github+json",
			["User-Agent"] = "Template-CI",
		},
		body = bytes,
	})
	Publication.RequireSuccess(result.status, `Upload release asset {name}`, { message = responseMessage(result.body) })
	return Publication.Record(Json.decode(result.body))
end

function Publication.RequireSuccess(status: number, operation: string, details: { [string]: unknown }?): ()
	if status < 200 or status >= 300 then
		local message = if details then details.message else nil
		local suffix = if type(message) == "string" and message ~= "" then `: {message}` else ""
		error(`{operation}: GitHub returned HTTP {status}{suffix}; check run permissions and repository policies`, 0)
	end
end

function Publication.Begin(setting: string): string?
	if Process.env.ACT == "true" then
		print(`Publication {setting}: skipped during local act execution`)
		return nil
	end
	if Process.env.GITHUB_ACTIONS ~= "true" then
		print(`Publication {setting}: skipped outside GitHub Actions`)
		return nil
	end
	local configuration = Configuration.new()
	if configuration.publication[setting:lower()] == false then
		print(`Publication {setting}: disabled in .github/config/targets.toml`)
		return nil
	end
	local repository = configuration:ResolveRepository(configuration.repository)
	if Process.env.GITHUB_REPOSITORY ~= repository or Process.env.CI_EVENT ~= "push" then
		error("Publication is allowed only for a push in the configured repository", 0)
	end
	local status, details = Publication.Request("GET", `repos/{repository}`)
	Publication.RequireSuccess(status, "Read publication repository", details)
	local defaultBranch = Publication.Text(details.default_branch)
	local graphRun = Process.env.CI_GRAPH_RUN == "true"
	local fixedStage = Process.env.CI_STAGE_MODE == "fixed"
	if fixedStage then
		if not graphRun or Process.env.CI_PHASE ~= "publish"
			or Process.env.GITHUB_REF ~= "refs/heads/source"
			or defaultBranch ~= "source"
			or (Process.env.GITHUB_EVENT_NAME ~= "push" and Process.env.GITHUB_EVENT_NAME ~= "workflow_dispatch") then
			error("Fixed publication requires a trusted source-branch Publish stage", 0)
		end
	elseif not graphRun and Process.env.GITHUB_REF ~= `refs/heads/{defaultBranch}` then
		error("Publication requires a push to the default branch", 0)
	end
	if graphRun and not fixedStage then
		local runBranch = Process.env.CI_RUN_BRANCH
		local suffix = if runBranch then runBranch:sub(#configuration.branchPrefix + 1) else ""
		if
			not runBranch
			or runBranch:sub(1, #configuration.branchPrefix) ~= configuration.branchPrefix
			or not suffix:match("^%d+%-%d+$")
			or Process.env.GITHUB_REF ~= `refs/heads/{runBranch}`
		then
			error("Publication requires the validated generated run branch", 0)
		end
	end
	return repository
end

function Publication.ReadIndex(path: string, field: string): { unknown }
	local index = Publication.Record(Json.decode(Fs.readFileToString(path)))
	local entries = index[field]
	if type(entries) ~= "table" then
		error(`{path}: missing {field} array`, 0)
	end
	local result: { unknown } = {}
	for _, entry in entries do
		table.insert(result, entry)
	end
	return result
end

return Publication
