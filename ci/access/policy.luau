--!strict
local policy = {}
local rules = require("../lib/rules")
local definition = rules.read("ci/access/publication.rules.json")

export type Context = {
    localRun: boolean?,
    actions: string?,
    server: string?,
    event: string?,
    ref: string?,
    repository: string?,
    eventRepository: string?,
}

-- Configuration selects eligible outputs; GitHub grants actual permissions.
-- Local event payloads are not proof of authorization.
function policy.canPublish(context: Context): boolean
    local valid = pcall(rules.validate, context, definition)
    return valid
end

return policy
