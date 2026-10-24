-- ci/preflight/init.luau
--!strict

-- The CLI boundary emits evidence; imported preflight modules have no effects.
local Preflight = {}

local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Stdio = require("@lune/stdio")
local Analyzer = require("@self/analyzer")

function Preflight.Run(args: { string })
    if #args == 1 and args[1] == "list" then
        Stdio.write(Serde.encode("json", {
            { id = "luau.analysis", kind = "static", scope = "all saved Luau files" },
        }, true) .. "\n")
        return
    end
    if #args ~= 1 or args[1] ~= "run" then
        Stdio.write("preflight expects list or run\n")
        Process.exit(2)
    end

    local outcome = Analyzer.Run()
    Stdio.write(Serde.encode("json", {
        origin = "local-preflight",
        scope = "all-saved-luau",
        results = { outcome },
    }, true) .. "\n")
    if outcome.status ~= "passed" then
        Process.exit(1)
    end
end

return Preflight
