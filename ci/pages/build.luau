-- ci/pages/build.luau
--!strict
local Fs = require("@lune/fs")
local Process = require("@lune/process")
local config = require("../lib/config").Read()
local Files = require("../lib/files")
assert(config.pages.enabled, "Pages generation is disabled")
Files.Reset("build/pages")
local function render(source, destination)
    Fs.writeDir(destination)
    for _, name in Fs.readDir(source) do
        local input = source .. "/" .. name
        if Fs.isDir(input) then
            render(input, destination .. "/" .. name)
        elseif name:match("%.md$") then
            local result = Process.exec("pandoc", {
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
            Files.Copy(input, destination .. "/" .. name)
        end
    end
end
render("ci/pages/templates", "build/pages")
assert(Fs.isFile("build/pages/index.html"), "Pages requires an index page")
print("Generated Pages at build/pages")
