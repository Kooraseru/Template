-- validation/run.luau
--!strict

local Validate = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Datetime = require("@lune/datetime")
local Test = require("@testing")
local Request = require("../.github/integration/request")
local Rules = require("../libraries/registry/rules")
local Policy = require("./policy")
local Repository = require("./repository")
local ReleaseValidation = require("../publication/releases/validate")
local ConfigTests = require("./tests/config")
local CatalogueTests = require("./tests/catalogue")
local ArtifactTests = require("./tests/artifacts")
local RuleTests = require("./tests/rules")
local GateTests = require("./tests/gate")
local WorkflowValidation = require("./workflows")
local AccessTests = require("../security/access/tests/policy")
local PublicationTests = require("../security/access/tests/publication")
local ControlTests = require("../.github/integration/tests/config")
local SourceApprovalTests = require("../.github/integration/tests/source-approval")
local PolicyTests = require("./tests/policy")
local ModuleTests = require("../.github/integration/tests/modules")
local RequestTests = require("../.github/integration/tests/request")
local CanonicalTests = require("./tests/canonical")
local ReceiptAuthenticationTests = require("../security/receipts/tests/authentication")
local TestingTests = require("./tests/testing")
local PluginTests = require("./tests/plugins")
local WorkshopTests = require("./tests/workshop")
local TargetTests = require("../fabricator/tests/targets")
local DiscoveryTests = require("../fabricator/tests/discovery")
local ProviderTests = require("./tests/providers")

--# Types

type Check = { path: string, Run: () -> () }
type Group = { name: string, checks: { Check } }

--# Helpers

local function runNodeTests(directory: string)
	local arguments = { "--test" }
	local names = Fs.readDir(directory)
	table.sort(names)

	for _, name in names do
		if name:sub(-9) == ".test.mjs" then
			table.insert(arguments, directory .. "/" .. name)
		end
	end

	assert(#arguments > 1, "test directory contains no legacy Node tests")
	local result = Process.exec("node", arguments, { stdio = "inherit" })
	assert(result.ok, "legacy release/receipt tests failed: " .. directory)
end

local function append(path: string, text: string)
	Fs.writeFile(path, (if Fs.isFile(path) then Fs.readFile(path) else "") .. text)
end

--# Functions

function Validate.Run(onStage: ((string, boolean) -> ())?)
	local controls = Request.Read()
	local revision = Process.exec("git", { "rev-parse", "HEAD" })
	assert(revision.ok, "cannot identify controller revision")
	local suiteReports: { Test.Report } = {}

	local function suiteCheck<Input, Output>(suite: Test.Suite<Input, Output>): () -> ()
		return function()
			suite:Run(function(report)
				table.insert(suiteReports, report)
			end)
		end
	end

	local groups: { Group } = {
		{
			name = "Configuration",
			checks = {
				{
					path = "validation/tests/testing.luau",
					Run = suiteCheck(TestingTests),
				},
				{
					path = "validation/tests/plugins.luau",
					Run = suiteCheck(PluginTests),
				},
				{
					path = "validation/tests/workshop.luau",
					Run = suiteCheck(WorkshopTests),
				},
				{
					path = "fabricator/tests/targets.luau",
					Run = suiteCheck(TargetTests),
				},
				{
					path = "fabricator/tests/discovery.luau",
					Run = suiteCheck(DiscoveryTests),
				},
				{
					path = "validation/tests/providers.luau",
					Run = suiteCheck(ProviderTests),
				},
				{ path = "validation/policy.luau", Run = Policy.Run },
				{ path = "validation/tests/policy.luau", Run = PolicyTests.Run },
				{ path = "validation/tests/canonical.luau", Run = CanonicalTests.Run },
				{ path = "validation/repository.luau", Run = Repository.Run },
				{ path = "publication/releases/validate.luau", Run = ReleaseValidation.Run },
				{
					path = "validation/tests/config.luau",
					Run = suiteCheck(ConfigTests),
				},
				{
					path = "validation/tests/catalogue.luau",
					Run = suiteCheck(CatalogueTests),
				},
				{ path = "validation/tests/artifacts.luau", Run = ArtifactTests.Run },
				{
					path = "validation/tests/rules.luau",
					Run = suiteCheck(RuleTests),
				},
				{
					path = "validation/tests/gate.luau",
					Run = suiteCheck(GateTests),
				},
			},
		},
		{
			name = "Workflow rules",
			checks = { { path = "validation/workflows.luau", Run = WorkflowValidation.Run } },
		},
		{
			name = "Access policy",
			checks = {
				{ path = "security/access/tests/policy.luau", Run = AccessTests.Run },
				{ path = "security/access/tests/publication.luau", Run = PublicationTests.Run },
				{ path = ".github/integration/tests/config.luau", Run = ControlTests.Run },
				{ path = ".github/integration/tests/source-approval.luau", Run = SourceApprovalTests.Run },
				{ path = ".github/integration/tests/request.luau", Run = RequestTests.Run },
				{ path = ".github/integration/tests/modules.luau", Run = ModuleTests.Run },
			},
		},
		{
			name = "Receipts",
			checks = {
				{ path = "security/receipts/tests/authentication.luau", Run = ReceiptAuthenticationTests.Run },
				{
					path = "security/receipts/tests",
					Run = function()
						runNodeTests("security/receipts/tests")
					end,
				},
			},
		},
		{
			name = "Release tooling",
			checks = {
				{
					path = "publication/releases/tests",
					Run = function()
						runNodeTests("publication/releases/tests")
					end,
				},
			},
		},
	}
	local evidence = {
		suites = suiteReports,
		schema = 1,
		controller_sha = revision.stdout:gsub("%s+$", ""),
		tested_sha = Process.env.CI_TESTED_SHA,
		controls = controls,
		created_at = Datetime.now():toIsoDate(),
		groups = {} :: { { name: string, checks: { { path: string, success: boolean, error: string? } } } },
		success = true,
	}
	local summary = {
		"\n## Validation results",
		"",
		"Scope: " .. controls.validation_scope,
		"",
		"| Suite | Result |",
		"| --- | --- |",
	}

	for _, group in groups do
		if controls.validation_scope ~= "All" and controls.validation_scope ~= group.name then
			continue
		end

		local checks = {}
		local passed = true

		if onStage then
			onStage(group.name, true)
		end

		for _, check in group.checks do
			local success, failure = pcall(check.Run)
			passed = passed and success
			table.insert(
				checks,
				{ path = check.path, success = success, error = if success then nil else tostring(failure) }
			)
		end

		if onStage then
			onStage(group.name, false)
		end

		evidence.success = evidence.success and passed
		table.insert(evidence.groups, { name = group.name, checks = checks })
		table.insert(summary, "| " .. group.name .. " | " .. (if passed then "Passed" else "Failed") .. " |")
	end

	Fs.writeDir("build/validation")
	Fs.writeFile("build/validation/evidence.json", Serde.encode("json", evidence, true))

	if Process.env.GITHUB_STEP_SUMMARY and Process.env.GITHUB_STEP_SUMMARY ~= "" then
		append(Process.env.GITHUB_STEP_SUMMARY, table.concat(summary, "\n") .. "\n")
	end

	local path = "build/tmp/releases/plan.json"

	if Fs.isFile(path) then
		local plan = Rules.Entries(Serde.decode("json", Fs.readFile(path)))
		plan.validation = evidence
		Fs.writeFile(path, Serde.encode("json", plan, true))
	end

	local failures = {}

	for _, group in evidence.groups do
		for _, check in group.checks do
			if not check.success then
				table.insert(failures, check.path .. ": " .. (check.error or "failed"))
			end
		end
	end

	assert(evidence.success, table.concat(failures, "\n"))
end

return Validate
