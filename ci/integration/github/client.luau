-- ci/integration/github/client.luau
--!strict

local Client = {}

--# Modules

local GitHub = require("../../libraries/bootstrap/github")
local Shape = require("../../libraries/registry/shape")

export type Record = Shape.Object

--# Functions

function Client.Object(value: unknown): Shape.Object
    assert(type(value) == "table", "expected GitHub object")
    return value :: Shape.Object
end

function Client.Array(value: unknown): { unknown }
    return Shape.Sequence(value)
end

function Client.Rest(path: string, method: string?, body: unknown?): unknown
    return GitHub.Api("repos/" .. GitHub.Repository() .. "/" .. path, method, body)
end

function Client.Graphql(query: string, variables: { [string]: unknown }): Shape.Object
    local response = Client.Object(GitHub.Api("graphql", "POST", { query = query, variables = variables }))
    assert(response.errors == nil, "GitHub GraphQL errors returned")
    return Client.Object(response.data)
end

function Client.Repository(): (string, string)
    local value = GitHub.Repository()
    local owner, name = value:match("^([^/]+)/([^/]+)$")
    assert(owner ~= nil and name ~= nil, "expected owner/repository")
    return owner, name
end

return Client
