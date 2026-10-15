-- ci/validation/repository.luau
--!strict
local Fs = require("@lune/fs")
local Rules = require("../lib/rules")
local config = require("../lib/config").Read()
local Catalogue = require("../lib/catalogue")
Catalogue.Validate(Catalogue.Read(config))
local definitions = Rules.Read("ci/validation/ruleset.json", "repository")

type Check = Rules.RepositoryCheck
local operations: { [string]: (Check) -> () } = {
    directory_entries = function(check)
        local entries = Fs.readDir(assert(check.path, "missing check path"))
        table.sort(entries)
        local expected = table.clone(assert(check.expected, "missing expected entries"))
        table.sort(expected)
        assert(
            table.concat(entries, "\n") == table.concat(expected, "\n"),
            "unexpected directory entries"
        )
    end,
    absent_files = function(check)
        for _, path in assert(check.paths, "missing check paths") do
            assert(not Fs.isFile(path), "unexpected file: " .. path)
        end
    end,
    existing_config_paths = function(check)
        for _, path in Rules.Entries(Rules.Property(config, assert(check.config_path, "missing config path"))) do
            assert(type(path) == "string", "expected configured path")
            assert(Fs.isFile(path) or Fs.isDir(path), "missing configured input: " .. path)
        end
    end,
    file_contains = function(check)
        assert(Fs.readFile(assert(check.path, "missing check path")):find(assert(check.text, "missing check text"), 1, true), "missing required file content")
    end,
}
for _, check in assert(definitions.checks, "missing repository checks") do
    local execute = assert(operations[check.operation], "unknown filesystem check")
    execute(check)
end
print("Repository data checks passed")
