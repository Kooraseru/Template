-- repo/ci/github/projectClient.luau
--!strict

local Net = require("@lune/net")
local Serde = require("@lune/serde")
local Publication = require("./publication")

local ProjectClient = {}
ProjectClient.__index = ProjectClient
export type Query = (query: string, variables: { [string]: unknown }) -> { [string]: unknown }
type Fields = { token: string }
export type ProjectClient = setmetatable<Fields, typeof(ProjectClient)>

function ProjectClient.new(token: string): ProjectClient
	local fields: Fields = { token = token }
	return setmetatable(fields, ProjectClient)
end

function ProjectClient.Query(
	self: ProjectClient,
	query: string,
	variables: { [string]: unknown }
): { [string]: unknown }
	local response = Net.request({
		url = "https://api.github.com/graphql",
		method = "POST",
		headers = { Authorization = `Bearer {self.token}`, ["Content-Type"] = "application/json" },
		body = Serde.encode("json", { query = query, variables = variables }),
	})
	if response.statusCode == 401 or response.statusCode == 403 then
		error("PROJECT_AUTH: Projects API rejected the credential or permissions", 0)
	end
	Publication.RequireSuccess(response.statusCode, "Projects GraphQL request")
	local result = Publication.Record(Serde.decode("json", response.body))
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
			error("PROJECT_AUTH: Projects credential needs account-level Projects read/write access", 0)
		end
		error(`Projects API: {message}`, 0)
	end
	return Publication.Record(result.data)
end

return ProjectClient
