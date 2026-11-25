-- dependencies/packages/core/dataFormats/github.luau
--!strict

local Json = require("@formats/json")
local Net = require("@lute/net/client")
local Process = require("@lute/process")

local Publication = {}

--- Percent-encode a GitHub REST path segment.
function Publication.Encode(value: string): string
	return (
		value:gsub("([^%w%-_%.~])", function(character: string): string
			return string.format("%%%02X", string.byte(character))
		end)
	)
end

--- Normalize a decoded response to its named fields.
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

--- Require a nonempty string from a GitHub response.
function Publication.Text(value: unknown): string
	if type(value) ~= "string" or value == "" then
		error("Expected a nonempty publication string", 0)
	end
	return value
end

--- Send an authenticated GitHub REST request with the job-scoped token.
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
			["User-Agent"] = "Template-CI",
		},
		body = if body ~= nil then Json.encode(body) else nil,
	})
	return response
end

--- Bound and redact error details before exposing them in logs.
local function responseMessage(body: string): string
	local token = Process.env.GH_TOKEN
	local safe = body:gsub("[%c]", " ")
	if token and token ~= "" then
		safe = safe:gsub(token:gsub("([^%w])", "%%%1"), "[redacted]")
	end
	return safe:sub(1, 240)
end

--- Return the HTTP status and decoded response object, retaining API errors.
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

--- Read a GitHub list and reject invalid HTTP statuses or response shapes.
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

--- Reject non-success HTTP statuses with bounded API context.
function Publication.RequireSuccess(status: number, operation: string, details: { [string]: unknown }?): ()
	if status < 200 or status >= 300 then
		local message = if details then details.message else nil
		local suffix = if type(message) == "string" and message ~= "" then `: {message}` else ""
		error(`{operation}: GitHub returned HTTP {status}{suffix}; check run permissions and repository policies`, 0)
	end
end

return Publication
