-- validation/workflows.luau
--!strict

local Workflows = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../libraries/registry/rules")

--# Types

type ControlCheck = {
	source: string,
	section: string?,
	path: string,
	default_type: string,
}

--# Helpers

local function readYaml(path: string): unknown
	local source = Fs.readFile(path)

	return Serde.decode("yaml", source)
end

local function validateControls(workflow: unknown, check: ControlCheck)
	local source = Fs.readFile(check.source)
	local document = Serde.decode("json", source)
	local controls = Rules.Entries(if check.section then Rules.Property(document, check.section) else document)
	local inputs = Rules.Entries(Rules.Property(workflow, check.path))
	local expectedCount = 0

	for key, rawDefinition in pairs(controls) do
		assert(type(key) == "string", "expected control name")

		local definition = Rules.Entries(rawDefinition)
		local rawInput = inputs[key]
		assert(rawInput ~= nil, "missing CI control: " .. key)

		local input = Rules.Entries(rawInput)
		local expectedType = definition.type or check.default_type

		assert(input.type == expectedType, "incorrect CI control type: " .. key)
		assert(input.default == definition.default, "incorrect CI control default: " .. key)

		if definition.options ~= nil then
			local choices = Rules.Array(definition.options)
			local offeredChoices = Rules.Array(input.options)

			for _, choice in ipairs(choices) do
				assert(type(choice) == "string", "expected control choice")
				assert(table.find(offeredChoices, choice), "missing CI choice: " .. key .. " / " .. choice)
			end
		end

		expectedCount += 1
	end

	local actualCount = 0

	for _ in pairs(inputs) do
		actualCount += 1
	end

	assert(actualCount == expectedCount, "workflow inputs differ from the control catalogue")
end

--# Functions

function Workflows.CheckBoundaries(workflow: unknown)
	local jobs = Rules.Entries(Rules.Property(workflow, "jobs"))
	local gate = Rules.Entries(jobs.gate)
	assert(gate.name == nil, "gate must retain its required status identity")
	assert(tostring(gate["if"]):find("always()", 1, true), "gate must evaluate failed dependencies")

	for _, name in { "validate", "build", "repository", "pages", "release", "images", "validation-receipt" } do
		assert(table.find(Rules.Array(gate.needs), name), "gate must observe stage: " .. name)
	end

	for _, name in { "validate", "build", "release", "gate", "publish-repository", "publish-pages", "publish-release" } do
		assert(jobs[name] ~= nil, "missing workflow stage: " .. name)
	end

	for _, name in { "images", "build", "repository", "pages", "release" } do
		local permissions = Rules.Entries(Rules.Entries(jobs[name]).permissions or {})

		for _, permission in permissions do
			assert(permission ~= "write", "generation stage requests write permission: " .. name)
		end
	end

	for _, name in { "publish-repository", "publish-pages", "publish-release" } do
		local job = Rules.Entries(jobs[name])
		assert(table.find(Rules.Array(job.needs), "gate"), "publication must depend on gate: " .. name)
		local condition = tostring(job["if"])

		for _, required in
			{
				"needs.gate.result == 'success'",
				"needs.validate.outputs.local_execution == 'false'",
				"github.ref == 'refs/heads/source'",
			}
		do
			assert(condition:find(required, 1, true), "missing publication boundary: " .. name .. " / " .. required)
		end
	end
end

function Workflows.CheckActions(workflow: unknown, actionRules: Rules.Document)
	local visited: { [string]: boolean } = {}

	local function inspect(document: unknown)
		local function visitSteps(steps: unknown)
			for _, rawStep in Rules.Array(steps) do
				local step = Rules.Entries(rawStep)
				local reference = step.uses

				if type(reference) == "string" and reference:sub(1, 2) == "./" then
					assert(not reference:find("..", 3, true), "local action must remain inside repository")
					local path = reference .. "/action.yml"

					if not visited[path] then
						visited[path] = true
						assert(Fs.isFile(path), "missing local action: " .. reference)
						local action = readYaml(path)
						Rules.Validate(action, actionRules)
						inspect(action)
					end
				end
			end
		end

		local fields = Rules.Entries(document)

		if fields.jobs ~= nil then
			for _, job in Rules.Entries(fields.jobs) do
				visitSteps(Rules.Entries(job).steps)
			end
		else
			visitSteps(Rules.Property(document, "runs.steps"))
		end
	end

	inspect(workflow)
end

function Workflows.Run()
	local definitions = Rules.Read("validation/ruleset.json", "workflows.rules")
	local workflow = readYaml(".github/workflows/ci.yml")
	local controlCheck = definitions.controls
	local actionRules = definitions.actions

	assert(controlCheck ~= nil, "missing control validation definition")
	assert(actionRules ~= nil, "missing action validation rules")

	Rules.Validate(workflow, definitions)
	Workflows.CheckBoundaries(workflow)
	Workflows.CheckActions(workflow, actionRules)
	validateControls(workflow, controlCheck)

	for _, name in ipairs(Fs.readDir(".github/actions")) do
		local path = ".github/actions/" .. name .. "/action.yml"

		if Fs.isFile(path) then
			local action = readYaml(path)

			Rules.Validate(action, actionRules)
		end
	end
end

return Workflows
