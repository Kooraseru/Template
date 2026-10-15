--!strict
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local policy = require("./policy")
local context = {}

function context.repository(event: any): string?
    if type(event) ~= "table" or type(event.repository) ~= "table" then
        return nil
    end
    local name = event.repository.full_name
    return if type(name) == "string" and name ~= "" then name else nil
end

function context.read(env: { [string]: string? }): policy.Context
    local repository: string? = nil
    if env.GITHUB_EVENT_PATH then
        local event = serde.decode("json", fs.readFile(env.GITHUB_EVENT_PATH))
        repository = context.repository(event)
    end

    local manualAllowed = false
    if env.GITHUB_EVENT_NAME == "workflow_dispatch" then
        manualAllowed = process.exec("node", { "ci/control/authorize-publication.mjs" }, { env = env }).ok
    end
    return {
        manualAllowed = manualAllowed,
        localRun = env.ACT == "true",
        actions = env.GITHUB_ACTIONS,
        server = env.GITHUB_SERVER_URL,
        event = env.GITHUB_EVENT_NAME,
        ref = env.GITHUB_REF,
        repository = env.GITHUB_REPOSITORY,
        eventRepository = repository,
    }
end

return context
