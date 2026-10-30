-- repo/ci/github/publication.luau
--!strict

local Fs = require("@lune/fs")
local Net = require("@lune/net")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Configuration = require("./configuration")

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
		local current = if Fs.isFile(path) then Fs.readFile(path) else ""
		Fs.writeFile(path, `{current}\n{name}={value}\n`)
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

function Publication.Request(
	method: "GET" | "POST" | "PATCH" | "PUT" | "DELETE",
	path: string,
	body: unknown?
): (number, { [string]: unknown })
	local token = Process.env.GH_TOKEN
	if not token or token == "" then
		error("Publication requires the run-provided GITHUB_TOKEN with the declared write permissions", 0)
	end
	local response = Net.request({
		url = `https://api.github.com/{path}`,
		method = method,
		headers = {
			Authorization = `Bearer {token}`,
			Accept = "application/vnd.github+json",
			["Content-Type"] = "application/json",
			["X-GitHub-Api-Version"] = "2022-11-28",
		},
		body = if body ~= nil then Serde.encode("json", body) else nil,
	})
	local decoded = if response.body ~= "" then Publication.Record(Serde.decode("json", response.body)) else {}
	return response.statusCode, decoded
end

function Publication.RequireSuccess(status: number, operation: string): ()
	if status < 200 or status >= 300 then
		error(`{operation}: GitHub returned HTTP {status}; check run permissions and repository policies`, 0)
	end
end

function Publication.Begin(setting: string): string?
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
	local index = Publication.Record(Serde.decode("json", Fs.readFile(path)))
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
