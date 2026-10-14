--!strict
local fs = require("@lune/fs")
local rules = require("../lib/rules")
local config = require("../lib/config").read()
local definitions = rules.read("ci/validation/repository.checks.json")

local operations: { [string]: (any) -> () } = {
    directory_entries = function(check)
        local entries = fs.readDir(check.path)
        table.sort(entries)
        local expected = table.clone(check.expected)
        table.sort(expected)
        assert(
            table.concat(entries, "\n") == table.concat(expected, "\n"),
            "unexpected directory entries"
        )
    end,
    absent_files = function(check)
        for _, path in check.paths do
            assert(not fs.isFile(path), "unexpected file: " .. path)
        end
    end,
    existing_config_paths = function(check)
        for _, path in rules.property(config, check.config_path) do
            assert(fs.isFile(path) or fs.isDir(path), "missing configured input: " .. path)
        end
    end,
    file_contains = function(check)
        assert(fs.readFile(check.path):find(check.text, 1, true), "missing required file content")
    end,
}
for _, check in definitions.checks do
    local execute = assert(operations[check.operation], "unknown filesystem check")
    execute(check)
end
print("Repository data checks passed")
