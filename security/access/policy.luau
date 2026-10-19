-- security/access/policy.luau
--!strict

local Policy = {}

--# Modules

local Rules = require("../../libraries/registry/rules")
local definition = Rules.Read("security/access/ruleset.json", "publication.rules")

--# Types

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

--# Functions

function Policy.CanPublish(context: unknown): boolean
	local valid = pcall(Rules.Validate, context, definition)

	return valid
end

return Policy
