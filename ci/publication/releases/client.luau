-- ci/publication/releases/client.luau
--!strict

local Client = {}

--# Modules

local Commands = require("../../libraries/bootstrap/commands")
local Canonical = require("../../libraries/bootstrap/canonical")
local Json = require("../../libraries/bootstrap/json")
local Task = require("@lune/task")

--# Types

export type Options = { Method: string?, Body: string?, ContentType: string?, Missing: boolean?, Binary: boolean? }
export type API = {
	Request: (string, Options?) -> Canonical.Value?,
	Bytes: (string, Options?) -> string?,
	JSON: (string, string, Canonical.Value) -> Canonical.Value,
	Pages: (string) -> { Canonical.Value },
}

--# Functions

function Client.new(repository: string): API
	assert(repository:match("^[%w_.%-]+/[%w_.%-]+$"), "invalid repository")
	local prefix = "repos/" .. repository
	local function bytes(route: string, options: Options?): string?
		local selected: Options = options or {}
		local endpoint: string
		if route:sub(1, 8) == "https://" then
			assert(route:match("^https://uploads%.github%.com/"), "unexpected GitHub API host")
			endpoint = route
		else
			assert(route:sub(1, 1) == "/", "expected repository API route")
			endpoint = prefix .. route
		end
		local method = selected.Method or "GET"
		local args = {
			"api",
			endpoint,
			"--method",
			method,
			"-H",
			if selected.Binary then "Accept: application/octet-stream" else "Accept: application/vnd.github+json",
		}
		if selected.Body then
			table.insert(args, "--input")
			table.insert(args, "-")
			table.insert(args, "-H")
			table.insert(args, "Content-Type: " .. (selected.ContentType or "application/json"))
		end
		for attempt = 1, 3 do
			local result = Commands.Execute("gh", args, selected.Body)
			if result.ok then
				return result.stdout
			end
			if selected.Missing and result.stderr:find("HTTP 404", 1, true) then
				return nil
			end
			if
				attempt < 3
				and table.find({ "GET", "PATCH", "DELETE" }, method)
				and result.stderr:match("HTTP 5%d%d")
			then
				Task.wait(attempt)
			else
				error("GitHub request failed: " .. result.stderr)
			end
		end
		error("GitHub retries exhausted")
	end
	local function request(route: string, options: Options?): Canonical.Value?
		local result = bytes(route, options)
		return if result and result:match("%S") then Canonical.Decode(result) else nil
	end
	local function json(method: string, route: string, value: Canonical.Value): Canonical.Value
		return (
			assert(request(route, { Method = method, Body = assert(Canonical.Encode(value)) }), "empty GitHub response")
		)
	end
	local function pages(route: string): { Canonical.Value }
		local result: { Canonical.Value } = {}
		for page = 1, math.huge do
			local batch = Json.Array(
				request(route .. (if route:find("?", 1, true) then "&" else "?") .. "per_page=100&page=" .. page)
			)
			for _, entry in batch do
				table.insert(result, entry)
			end
			if #batch < 100 then
				break
			end
		end
		return result
	end
	return { Request = request, Bytes = bytes, JSON = json, Pages = pages }
end

return Client
