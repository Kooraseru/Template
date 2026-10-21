-- ci/publication/releases/validate.luau
--!strict

local ValidateReleases = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Inputs = require("../../libraries/bootstrap/inputs")
local Versions = require("./versions")

--# Functions

function ValidateReleases.Run()
	local previousValue = Inputs.ref
	local success, failure = pcall(function()
		-- Inspect proposed configuration as data using the trusted controller parser.
		Inputs.ref = Process.env.CI_TESTED_SHA or previousValue
		local document = Serde.decode("toml", Inputs.Read("ci/publication/releases/versions.toml"))
		local source = Process.exec("git", { "rev-parse", "HEAD" })

		assert(source.ok, "cannot resolve trusted source controller")
		Fs.writeDir("build/tmp/releases")
		Fs.writeFile(
			"build/tmp/releases/validation.json",
			Serde.encode("json", {
				versions = document,
				source_tip = source.stdout:gsub("%s+$", ""),
			})
		)
		for _, release in Versions.Validate(document, (source.stdout:gsub("%s+$", ""))) do
			if release.notes then
				Inputs.Read(release.notes)
			end
		end
	end)

	Inputs.ref = previousValue

	assert(success, tostring(failure))
end

return ValidateReleases
