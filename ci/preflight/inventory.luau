-- ci/preflight/inventory.luau
--!strict

-- Read saved Luau sources as data. Discovery never requires them.
local Inventory = {}

local Fs = require("@lune/fs")
local Process = require("@lune/process")

export type Snapshot = {
    files: { string },
    error: string?,
}

function Inventory.Read(): Snapshot
    local ok, execution = pcall(Process.exec, "git", {
        "ls-files", "-co", "--exclude-standard", "--deduplicate", "-z", "--", "*.luau",
    })
    if not ok then
        return { files = {}, error = "cannot inspect repository inventory: " .. tostring(execution) }
    end
    if not execution.ok then
        return { files = {}, error = "git inventory failed: " .. execution.stderr }
    end

    local files = {}
    local seen: { [string]: boolean } = {}
    for path in execution.stdout:gmatch("[^%z]+") do
        if path:match("%.luau$") and Fs.isFile(path) and not seen[path] then
            seen[path] = true
            table.insert(files, path)
        end
    end
    table.sort(files)
    if #files == 0 then
        return { files = {}, error = "no saved Luau sources were discovered" }
    end
    return { files = files }
end

return Inventory
