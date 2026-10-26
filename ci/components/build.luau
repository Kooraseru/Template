-- ci/components/build.luau
--!strict
--[[ci-contract
provides = ["build.completed"]
requires = []
inputs = ["source/main.c", "source/hosts/*/init.luau"]
outputs = ["build/*.exe"]
end-ci-contract]]

-- The build component glues discovered host modules to shared source.
-- It has no compiler, image, target, or OS knowledge.
local Fs = require("@lune/fs")
local Glob = require("../bootstrap/glob")

return function(_context)
    if not Fs.isDir("build") then
        Fs.writeDir("build")
    end

    local entries = Glob.Find("source/hosts/*/init.luau")
    if #entries == 0 then
        error("No conforming host modules discovered", 0)
    end

    for _, entry in entries do
        local modulePath = "../../" .. entry:gsub("/init%.luau$", "")
        local host = require(modulePath)
        if type(host) ~= "function" then
            error(`{entry}: host module must return a callable function`, 0)
        end
        host()
        print(`Built host from {entry}`)
    end
end
