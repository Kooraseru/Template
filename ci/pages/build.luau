--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local config = require("../lib/config").read()
local files = require("../lib/files")
assert(config.pages.enabled, "Pages generation is disabled")
files.reset("build/pages")
local function render(source, destination)
    fs.writeDir(destination)
    for _, name in fs.readDir(source) do
        local input = source .. "/" .. name
        if fs.isDir(input) then
            render(input, destination .. "/" .. name)
        elseif name:match("%.md$") then
            local result = process.exec("pandoc", {
                "--standalone",
                "--from=gfm",
                "--metadata",
                "title=" .. config.pages.title,
                "--output",
                destination .. "/" .. name:gsub("%.md$", ".html"),
                input,
            })
            assert(result.ok, "pandoc failed: " .. result.stderr)
        else
            files.copy(input, destination .. "/" .. name)
        end
    end
end
render("ci/pages/templates", "build/pages")
assert(fs.isFile("build/pages/index.html"), "Pages requires an index page")
print("Generated Pages at build/pages")
