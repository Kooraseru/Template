--!strict
local fs = require("@lune/fs")
local outputs = {}
local rules = require("./rules")
local definition = rules.read("ci/access/outputs.rules.json")

function outputs.encode(values: { [string]: string }): string
    rules.validate(values, definition)
    local keys = {}
    for key, value in values do
        assert(key:match(definition.key_pattern), "invalid workflow output name")
        table.insert(keys, key)
    end
    table.sort(keys)

    local lines = {}
    for _, key in keys do
        table.insert(lines, key .. "=" .. values[key])
    end
    return table.concat(lines, "\n") .. "\n"
end

function outputs.write(path: string?, values: { [string]: string })
    local text = outputs.encode(values)
    if path then
        local existing = if fs.isFile(path) then fs.readFile(path) else ""
        fs.writeFile(path, existing .. text)
    end
    print("Resolved workflow context (matrices are written to workflow outputs)")
end

return outputs
