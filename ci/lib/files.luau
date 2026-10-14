--!strict
local fs = require("@lune/fs")
local config = require("./config")
local files = {}
function files.reset(path: string)
    config.relative(path)
    assert(path:sub(1, 6) == "build/", "only build/ output may be reset")
    if fs.isDir(path) then
        fs.removeDir(path)
    end
    fs.writeDir(path)
end
function files.copy(source: string, destination: string, excludeBuildState: boolean?)
    if fs.isDir(source) then
        fs.writeDir(destination)
        for _, name in fs.readDir(source) do
            if not excludeBuildState or (name ~= "target" and name ~= ".git") then
                files.copy(source .. "/" .. name, destination .. "/" .. name, excludeBuildState)
            end
        end
    else
        assert(fs.isFile(source), "missing input: " .. source)
        local parent = destination:match("^(.*)/[^/]+$")
        if parent then
            fs.writeDir(parent)
        end
        fs.copy(source, destination, true)
    end
end
return files
