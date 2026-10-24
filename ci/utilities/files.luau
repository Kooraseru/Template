-- ci/utilities/files.luau
--!strict

local Files = {}

--# Modules

local Fs = require("@lune/fs")
local Config = require("../fabricator/config")

--# Functions

function Files.Reset(path: string)
	Config.Relative(path)
	assert(path:sub(1, 6) == "build/", "only build/ output may be reset")

	if Fs.isDir(path) then
		Fs.removeDir(path)
	end
	Fs.writeDir(path)
end

function Files.Copy(source: string, destination: string, excludeBuildState: boolean?)
	if Fs.isDir(source) then
		Fs.writeDir(destination)

		for _, name in Fs.readDir(source) do
			if not excludeBuildState or (name ~= "target" and name ~= ".git") then
				Files.Copy(source .. "/" .. name, destination .. "/" .. name, excludeBuildState)
			end
		end
	else
		assert(Fs.isFile(source), "missing input: " .. source)
		local parent = destination:match("^(.*)/[^/]+$")

		if parent then
			Fs.writeDir(parent)
		end
		Fs.copy(source, destination, true)
	end
end

return Files
