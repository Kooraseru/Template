-- ci/lib/fixtures.luau
--!strict
local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Stdio = require("@lune/stdio")
local Files = require("./files")
local Config = require("./config")
local Cases = require("./cases")

return function(path: string)
    local definition = Cases.Read(path)
    local root = Config.Relative(definition.root)
    Files.Reset(root)
    for name, contents in definition.files do
        Config.Relative(name)
        local destination = root .. "/" .. name
        local parent = destination:match("^(.*)/[^/]+$")
        if parent then
            Fs.writeDir(parent)
        end
        Fs.writeFile(destination, contents)
    end
    for index, command in definition.commands do
        local source = if Process.os == "windows" and command.windows_argv
            then command.windows_argv
            else command.argv
        local arguments: { string } = {}
        for _, argument in source do
            table.insert(arguments, (argument:gsub("{root}", function()
                return root
            end)))
        end
        local executable = assert(table.remove(arguments, 1), "missing fixture executable")
        local result = Process.exec(executable, arguments)
        print(result.stdout)
        Stdio.ewrite(result.stderr)
        assert(result.code == command.code, "fixture command " .. tostring(index) .. " failed")
        if command.stdout_contains then
            assert(
                result.stdout:find(command.stdout_contains, 1, true),
                "missing expected fixture output"
            )
        end
    end
    print("Fixture checks passed: " .. path)
end
