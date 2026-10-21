-- ci/fabricator/tests/fixture.luau
--!strict

local FixtureTests = {}

--# Modules

local Fixtures = require("../../libraries/testing/fixtures")

--# Functions

function FixtureTests.Run()
	Fixtures.Run("ci/fabricator/ruleset.json", "package.cases")
end

return FixtureTests
