-- ci/access/context.luau
--!strict

local Context = {}
local Process = require("@lune/process")
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Policy = require("./policy")
local Rules = require("../lib/rules")

function Context.Repository(event: unknown): string?
    if type(event) ~= "table" then return nil end
    local repository = Rules.Entries(event).repository
    if type(repository) ~= "table" then
        return nil
    end
    local name = Rules.Entries(repository).full_name
    return if type(name) == "string" and name ~= "" then name else nil
end

function Context.Read(env: { [string]: string? }): Policy.Context
    local repository: string? = nil
    if env.GITHUB_EVENT_PATH then
        local event = Serde.decode("json", Fs.readFile(env.GITHUB_EVENT_PATH))
        repository = Context.Repository(event)
    end

    local executionEnv: { [string]: string } = {}
    for key, value in env do
        if value ~= nil then executionEnv[key] = value end
    end
    local manualAllowed = false
    if env.GITHUB_EVENT_NAME == "workflow_dispatch" then
        manualAllowed = Process.exec("node", { "ci/control/authorize-publication.mjs" }, { env = executionEnv }).ok
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

return Context
