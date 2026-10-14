--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local cases = {}

function cases.read(path: string): any
    return serde.decode("json", fs.readFile(path))
end

local function copy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in value do
        result[key] = copy(child)
    end
    return result
end

function cases.apply(baseline: any, case: any): any
    local result = copy(baseline)
    for path, value in case.patch or {} do
        local parts = string.split(path, ".")
        local parent = result
        for index = 1, #parts - 1 do
            parent = parent[tonumber(parts[index]) or parts[index]]
        end
        parent[tonumber(parts[#parts]) or parts[#parts]] = copy(value)
    end
    for _, key in case.remove or {} do
        local parts = string.split(key, ".")
        local parent = result
        for index = 1, #parts - 1 do
            parent = parent[tonumber(parts[index]) or parts[index]]
        end
        parent[tonumber(parts[#parts]) or parts[#parts]] = nil
    end
    return result
end

function cases.check(name: string, valid: boolean, operation: () -> any, expected: any?)
    local ok, result = pcall(operation)
    assert(ok == valid, name .. ": unexpected validation result")
    if ok and expected ~= nil then
        assert(result == expected, name .. ": unexpected return value")
    end
end

return cases
