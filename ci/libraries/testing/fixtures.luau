-- ci/libraries/testing/fixtures.luau
--!strict

local Fixtures = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Files = require("../bootstrap/files")
local Config = require("../registry/config")
local Cases = require("./cases")

--# Functions

function Fixtures.Run(path: string, section: string?)
	local definition = Cases.Read(path, section)
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
		local source = if Process.os == "windows" and command.windows_argv then command.windows_argv else command.argv
		local arguments: { string } = {}

		for _, argument in source do
			table.insert(arguments, (argument:gsub("{root}", function()
				return root
			end)))
		end

		local executable = assert(table.remove(arguments, 1), "missing fixture executable")
		local result = Process.exec(executable, arguments)
		assert(result.code == command.code, "fixture command " .. tostring(index) .. " failed: " .. result.stderr)

		if command.stdout_contains then
			assert(result.stdout:find(command.stdout_contains, 1, true), "missing expected fixture output")
		end
	end
end

return Fixtures
