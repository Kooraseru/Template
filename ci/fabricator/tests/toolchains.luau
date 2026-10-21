-- fabricator/tests/toolchains.luau
--!strict

local ToolchainTests = {}

--# Modules

local Fixtures = require("../../libraries/testing/fixtures")

--# Functions

function ToolchainTests.Run()
	Fixtures.Run("fabricator/ruleset.json", "toolchains.cases")
end

return ToolchainTests
