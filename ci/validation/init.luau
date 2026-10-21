-- ci/validation/init.luau
--!strict

-- Coherent validation API; this is an importable module, not an executable CI entry.
local Validation = {}

local Checks = require("@self/run")
local Conformance = require("@self/template")

function Validation.Run(onStage: ((string, boolean) -> ())?)
    Checks.Run(onStage)
end

function Validation.Conformance(args: { string })
    Conformance.Run(args)
end

return Validation
