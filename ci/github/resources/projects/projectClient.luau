-- ci/github/resources/projects/projectClient.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local Net = require("@lute/net/client")
local Publication = require("@ci/github/publication")

const QUERY_PATH = "ci/components/work/projects/sync/query.graphql"

local ProjectClient = {}
ProjectClient.__index = ProjectClient
export type Query = (operation: string, variables: { [string]: unknown }) -> { [string]: unknown }
type Fields = { document: string, token: string }
export type ProjectClient = setmetatable<Fields, typeof(ProjectClient)>

function ProjectClient.new(token: string): ProjectClient
	local fields: Fields = { document = Fs.readFileToString(QUERY_PATH), token = token }
	return setmetatable(fields, ProjectClient)
end

function ProjectClient.Query(
	self: ProjectClient,
	operation: string,
	variables: { [string]: unknown }
): { [string]: unknown }
	local response = Net.request("https://api.github.com/graphql", {
		method = "POST",
		headers = { Authorization = `Bearer {self.token}`, ["Content-Type"] = "application/json" },
		body = Json.encode({
			query = self.document,
			operationName = operation,
			variables = variables,
		}),
	})
	if response.status == 401 or response.status == 403 then
		error(`PROJECT_AUTH: {operation} returned HTTP {response.status}`, 0)
	end
	Publication.RequireSuccess(response.status, "Projects GraphQL request")
	local result = Publication.Record(Json.decode(response.body))
	local errors = result.errors
	if type(errors) == "table" and #errors > 0 then
		local first: { [string]: unknown } = {}
		for _, item in errors do
			first = Publication.Record(item)
			break
		end
		local message = if type(first.message) == "string" then first.message else "Unknown GraphQL error"

		if
			first.type == "FORBIDDEN"
			or first.type == "INSUFFICIENT_SCOPES"
			or message:find("required scopes", 1, true)
		then
			local category = if first.type == "FORBIDDEN" then "FORBIDDEN" else "INSUFFICIENT_SCOPES"
			error(`PROJECT_AUTH: {operation} returned {category}`, 0)
		end

		error(`Projects API: {message}`, 0)
	end
	return Publication.Record(result.data)
end

return ProjectClient
