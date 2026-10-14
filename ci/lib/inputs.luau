--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local inputs = { ref = process.env.CI_INPUT_REF or "" }
function inputs.read(path: string): string
    if inputs.ref == "" then
        return fs.readFile(path)
    end
    local result = process.exec("git", { "show", inputs.ref .. ":" .. path })
    assert(result.ok, "missing selected commit input: " .. path .. "\n" .. result.stderr)
    return result.stdout
end
return inputs
