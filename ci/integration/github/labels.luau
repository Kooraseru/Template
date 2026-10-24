-- ci/integration/github/labels.luau
--!strict

local Labels = {}

--# Modules

local Stdio = require("@lune/stdio")

local Definitions = require("./definitions")
local Client = require("./client")

--# Helpers

local function emit(message: string)
    Stdio.write(message .. "\n")
end

--# Functions

function Labels.Run(operation: string)
    local declared = Definitions.ReadLabels()
    if operation == "validate" then
        emit("Validated " .. #declared .. " label definitions")
        return
    end

    local actual: { [string]: Client.Record } = {}
    for page = 1, 20 do
        local batch = Client.Array(Client.Rest("labels?per_page=100&page=" .. page))
        for _, entry in batch do
            local label = Client.Object(entry)
            local name = assert(label.name, "label missing name")
            assert(type(name) == "string", "invalid remote label")
            actual[name] = label
        end
        if #batch < 100 then
            break
        end
        assert(page < 20, "label pagination limit exceeded")
    end

    local changes = 0
    for _, wanted in declared do
        local current = actual[wanted.name]
        if current == nil then
            emit("CREATE label " .. wanted.name)
            changes += 1
            if operation == "apply" then
                Client.Rest("labels", "POST", {
                    name = wanted.name, color = wanted.color, description = wanted.description,
                })
            end
        elseif current.color ~= wanted.color or current.description ~= wanted.description then
            emit("UPDATE label " .. wanted.name)
            changes += 1
            if operation == "apply" then
                Client.Rest("labels/" .. wanted.name, "PATCH", {
                    color = wanted.color, description = wanted.description,
                })
            end
        end
    end

    emit("Labels: " .. changes .. " proposed change(s)")
end

return Labels
