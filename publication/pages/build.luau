-- publication/pages/build.luau
--!strict

local Pages = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Files = require("../../libraries/bootstrap/files")
local Config = require("../../libraries/registry/config")

--# Helpers

local function render(source: string, destination: string, title: string)
	Fs.writeDir(destination)

	for _, name in Fs.readDir(source) do
		local input = source .. "/" .. name

		if Fs.isDir(input) then
			render(input, destination .. "/" .. name, title)
		elseif name:match("%.md$") then
			local result = Process.exec("pandoc", {
				"--standalone",
				"--from=gfm",
				"--metadata",
				"title=" .. title,
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

--# Functions

function Pages.Run()
	local config = Config.Read()

	assert(config.pages.enabled, "Pages generation is disabled")
	Files.Reset("build/pages")
	render("publication/pages/templates", "build/pages", config.pages.title)
	assert(Fs.isFile("build/pages/index.html"), "Pages requires an index page")
end

return Pages
