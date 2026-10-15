-- ci/access/policy.luau
--!strict

local Policy = {}
local Rules = require("../lib/rules")
local definition = Rules.Read("ci/access/publication.rules.json")

export type Context = {
    localRun: boolean?,
    manualAllowed: boolean?,
    actions: string?,
    server: string?,
    event: string?,
    ref: string?,
    repository: string?,
    eventRepository: string?,
}

-- Configuration selects eligible outputs; GitHub grants actual permissions.
-- Local event payloads are not proof of authorization.
function Policy.CanPublish(context: unknown): boolean
    local valid = pcall(Rules.Validate, context, definition)
    return valid
end

return Policy
