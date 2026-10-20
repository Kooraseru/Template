-- .github/integration/tests/source-promotion.luau
--!strict

local Test = require("@testing")

--# Modules

local Serde = require("@lune/serde")
local Publication = require("../publication")
local Request = require("../request")
local Gate = require("../gate")

--# Types

type Input = {
	Kind: string?,
	Validation: boolean?,
	Build: string?,
	Receipt: string?,
	Administrator: boolean?,
	Scope: string?,
	Override: boolean?,
}

--# Helpers

local function eligible(input: Input): boolean

	local controls = Request.Normalize({}, false)
	controls.validation_scope = input.Scope or "All"
	controls.gate_policy = if input.Override then "Ignore both" else "Enforce all"
	local plan = {
		validation = { success = input.Validation },
		context = {
			source_authorization = if input.Kind
				then { kind = input.Kind, actor = "administrator", source_sha = string.rep("a", 40) }
				else nil,
		},
	}
	local before = Serde.encode("json", plan)
	local errors = Gate.Check(controls, {
		validate = { result = "success" },
		build = { result = input.Build or "success" },
		["validation-receipt"] = { result = input.Receipt or "success" },
	}, {}, plan, "push")
	assert(Serde.encode("json", plan) == before, "promotion checks mutated source evidence")
	local authorized = pcall(Publication.Authorize, {
		GITHUB_ACTIONS = "true",
		GITHUB_SERVER_URL = "https://github.com",
		GITHUB_EVENT_NAME = "push",
		GITHUB_REF = "refs/heads/source",
		GITHUB_ACTOR = "administrator",
	}, function(actor)
		return actor == "administrator" and input.Administrator ~= false
	end)

	return authorized and #errors == 0
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Source authority and downstream promotion",
	Execute = eligible,
	Cases = {
		{
			Name = "Validated direct administrator push needs no second acceptance",
			Input = { Kind = "admin-source-push", Validation = true },
			Expected = true,
		},
		{
			Name = "Validated administrator merge is eligible",
			Input = { Kind = "admin-merge", Validation = true },
			Expected = true,
		},
		{
			Name = "Failed validation blocks direct-push promotion",
			Input = { Kind = "admin-source-push", Validation = false },
			Expected = false,
		},
		{
			Name = "Missing validation evidence blocks promotion",
			Input = { Kind = "admin-source-push" },
			Expected = false,
		},
		{
			Name = "Build failure blocks promotion",
			Input = { Kind = "admin-source-push", Validation = true, Build = "failure" },
			Expected = false,
		},
		{
			Name = "Missing receipt blocks promotion",
			Input = { Kind = "admin-source-push", Validation = true, Receipt = "skipped" },
			Expected = false,
		},
		{ Name = "Unrecognized source update cannot promote", Input = { Validation = true }, Expected = false },
		{
			Name = "Unknown source authority cannot promote",
			Input = { Kind = "unknown", Validation = true },
			Expected = false,
		},
		{
			Name = "Unauthorized actor cannot publish",
			Input = { Kind = "admin-source-push", Validation = true, Administrator = false },
			Expected = false,
		},
		{
			Name = "Reduced source validation cannot promote",
			Input = { Kind = "admin-source-push", Validation = true, Scope = "Receipts" },
			Expected = false,
		},
		{
			Name = "Source pushes cannot use gate overrides",
			Input = { Kind = "admin-source-push", Validation = false, Override = true },
			Expected = false,
		},
	},
}

return Test.new(definition)
