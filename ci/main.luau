--!strict
-- The only public Luau command dispatcher. Do not execute arbitrary file paths.
local Process = require("@lune/process")
local AgentRules = require("./libraries/registry/agent-rules")

local args = Process.args
local operation = args[1]

if operation == "rules" and args[2] == "sync" and not args[3] then
    AgentRules.Sync()
elseif operation == "rules" and args[2] == "check" and not args[3] then
    AgentRules.Check()
elseif operation == "validate" and not args[2] then
    -- Temporary bridge during migration; retired when validation moves under ci/.
    local Validate = require("../validation/run")
    Validate.Run()
elseif operation == "native-compat" and not args[2] then
    local result = Process.exec("node", { "--test", "ci/libraries/bootstrap/native.test.mjs" })
    print(result.stdout)
    assert(result.ok, result.stderr)
else
    error("Unknown operation. Supported: rules sync, rules check, validate, native-compat", 0)
end
