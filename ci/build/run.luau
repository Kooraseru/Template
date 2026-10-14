--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local config = require("../lib/config").read()
fs.writeDir("build/logs")
for index, command in config.build.commands do
    local arguments = table.clone(command)
    local executable = assert(table.remove(arguments, 1), "configured command has no executable")
    print("Running configured command " .. tostring(index) .. ": " .. executable)
    local result =
        process.exec(executable, arguments, { env = { CARGO_TARGET_DIR = "build/cargo" } })
    fs.writeFile("build/logs/command-" .. tostring(index) .. ".log", result.stdout .. result.stderr)
    print(result.stdout)
    if result.stderr ~= "" then
        stdio.ewrite(result.stderr)
    end
    assert(result.ok, "configured build command failed with exit code " .. tostring(result.code))
end
if #config.build.commands == 0 then
    fs.writeFile("build/logs/build.log", "No project build commands configured.\n")
    print("No project build commands configured")
end
