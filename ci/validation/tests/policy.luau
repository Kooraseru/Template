-- ci/validation/tests/policy.luau
--!strict

local PolicyTests = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../../libraries/registry/rules")
local Policy = require("../policy")

--# Functions

function PolicyTests.Run()
	local document = Rules.Entries(Serde.decode("json", Fs.readFile("ci/validation/ruleset.json")))
	local cases = Rules.Array(Rules.Entries(document.luau).cases)
	local definition = Policy.Read()

	for _, raw in cases do
		local case = Rules.Entries(raw)
		assert(
			type(case.source) == "string" and type(case.file) == "string" and type(case.valid) == "boolean",
			"invalid source policy case"
		)
		local errors = Policy.CheckModule(case.source, case.file, definition)
		assert((#errors == 0) == case.valid, tostring(case.name) .. ": " .. table.concat(errors, "; "))
	end
end

return PolicyTests
