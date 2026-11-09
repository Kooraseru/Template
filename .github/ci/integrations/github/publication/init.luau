-- .github/ci/integrations/github/publication/init.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local Net = require("@lute/net/client")
local Process = require("@lute/process")
local Configuration = require("@ci/integrations/github/configuration")

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
	local response = Net.request(`https://api.github.com/{path}`, {
		method = method,
		headers = {
			Authorization = `Bearer {token}`,
			Accept = "application/vnd.github+json",
			["Content-Type"] = "application/json",
			["X-GitHub-Api-Version"] = "2022-11-28",
		},
		body = if body ~= nil then Json.encode(body) else nil,
	})
	return response
end

function Publication.Request(
	method: "GET" | "POST" | "PATCH" | "PUT" | "DELETE",
	path: string,
	body: unknown?
): (number, { [string]: unknown })
	local result = response(method, path, body)
	local decoded = if result.body ~= "" then Publication.Record(Json.decode(result.body)) else {}
	return result.status, decoded
end

function Publication.List(path: string): { unknown }
	local result = response("GET", path, nil)
	Publication.RequireSuccess(result.status, "Read GitHub list")
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
	local result = Net.request(`https://uploads.github.com/repos/{repository}/releases/{releaseId}/assets?name={Publication.Encode(name)}`, {
		method = "POST",
		headers = {
			Authorization = `Bearer {token}`,
			["Content-Type"] = "application/octet-stream",
			Accept = "application/vnd.github+json",
		},
		body = bytes,
	})
	Publication.RequireSuccess(result.status, `Upload release asset {name}`)
	return Publication.Record(Json.decode(result.body))
end

function Publication.RequireSuccess(status: number, operation: string): ()
	if status < 200 or status >= 300 then
		error(`{operation}: GitHub returned HTTP {status}; check run permissions and repository policies`, 0)
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
	local enabled = Process.env[`CI_PUBLISH_{setting}`]
	if enabled and enabled ~= "" and enabled ~= "true" and enabled ~= "false" then
		error(`CI_PUBLISH_{setting} must be true, false, or unset`, 0)
	end
	if enabled == "false" then
		print(`Publication {setting}: disabled by GitHub variable CI_PUBLISH_{setting}`)
		return nil
	end
	local configuration = Configuration.new()
	local repository = configuration:ResolveRepository(configuration.repository)
	if Process.env.GITHUB_REPOSITORY ~= repository or Process.env.CI_EVENT ~= "push" then
		error("Publication is allowed only for a push in the configured repository", 0)
	end
	local status, details = Publication.Request("GET", `repos/{repository}`)
	Publication.RequireSuccess(status, "Read publication repository")
	local defaultBranch = Publication.Text(details.default_branch)
	local graphRun = Process.env.CI_GRAPH_RUN == "true"
	if not graphRun and Process.env.GITHUB_REF ~= `refs/heads/{defaultBranch}` then
		error("Publication requires a push to the default branch", 0)
	end
	if graphRun then
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
