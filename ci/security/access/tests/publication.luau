-- ci/security/access/tests/publication.luau
--!strict

local PublicationTests = {}

--# Modules

local Process = require("@lune/process")
local Cases = require("../../../libraries/testing/cases")

--# Functions

function PublicationTests.Run()
	local definitions = Cases.Read("ci/security/access/ruleset.json", "publication.cases")

	for _, script in definitions.scripts do
		for _, case in definitions.cases do
			local arguments = table.clone(case.arguments)
			table.insert(arguments, script)
			local result = Process.exec("bash", arguments, { env = case.env })

			assert(result.ok == case.ok, script .. ": " .. case.name .. " returned an unexpected result")
		end
	end
end

return PublicationTests
