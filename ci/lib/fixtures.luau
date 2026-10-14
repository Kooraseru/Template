--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local files = require("./files")
local config = require("./config")
local cases = require("./cases")
local fixtures = {}

function fixtures.run(path: string)
    local definition = cases.read(path)
    local root = config.relative(definition.root)
    files.reset(root)
    for name, contents in definition.files do
        config.relative(name)
        local destination = root .. "/" .. name
        local parent = destination:match("^(.*)/[^/]+$")
        if parent then
            fs.writeDir(parent)
        end
        fs.writeFile(destination, contents)
    end
    for index, command in definition.commands do
        local source = if process.os == "windows" and command.windows_argv
            then command.windows_argv
            else command.argv
        local arguments: { string } = {}
        for _, argument in source do
            table.insert(arguments, (argument:gsub("{root}", function()
                return root
            end)))
        end
        local executable = assert(table.remove(arguments, 1), "missing fixture executable")
        local result = process.exec(executable, arguments)
        print(result.stdout)
        stdio.ewrite(result.stderr)
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
return fixtures
