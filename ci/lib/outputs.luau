-- ci/lib/outputs.luau
--!strict

local Outputs = {}
local Fs = require("@lune/fs")
local Rules = require("./rules")
local definition = Rules.Read("ci/access/outputs.rules.json")

function Outputs.Encode(raw: unknown): string
    Rules.Validate(raw, definition)
    local values = raw :: { [string]: string }
    local keys: { string } = {}
    local keyPattern = assert(definition.key_pattern, "missing workflow output key pattern")
    for key in values do
        assert(key:match(keyPattern), "invalid workflow output name")
        table.insert(keys, key)
    end
    table.sort(keys)

    local lines = {}
    for _, key in keys do
        table.insert(lines, key .. "=" .. values[key])
    end
    return table.concat(lines, "\n") .. "\n"
end

function Outputs.Write(path: string?, values: { [string]: string })
    local text = Outputs.Encode(values)
    if path then
        local existing = if Fs.isFile(path) then Fs.readFile(path) else ""
        Fs.writeFile(path, existing .. text)
    end
    print("Resolved workflow context (matrices are written to workflow outputs)")
end

return Outputs
