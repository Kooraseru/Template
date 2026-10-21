-- ci/validation/run.luau
--!strict

local Validate = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Datetime = require("@lune/datetime")
local Test = require("../libraries/testing/test")
local Request = require("../integration/request")
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
local ControlTests = require("../integration/tests/config")
local SourceApprovalTests = require("../integration/tests/source-approval")
local SourcePromotionTests = require("../integration/tests/source-promotion")
local PolicyTests = require("./tests/policy")
local ModuleTests = require("../integration/tests/modules")
local RequestTests = require("../integration/tests/request")
local CanonicalTests = require("./tests/canonical")
local ReceiptAuthenticationTests = require("../security/receipts/tests/authentication")
local TestingTests = require("./tests/testing")
local PluginTests = require("./tests/plugins")
local ActivationTests = require("./tests/activation")
local WorkflowTests = require("./tests/workflows")
local TemplateTests = require("./tests/template")
local CoverageTests = require("../fabricator/tests/coverage")
local WorkshopTests = require("./tests/workshop")
local TargetTests = require("../fabricator/tests/targets")
local DiscoveryTests = require("../fabricator/tests/discovery")
local ProviderTests = require("./tests/providers")
local ReceiptBundleTests = require("../security/receipts/tests/bundles")
local VersionTests = require("../publication/releases/tests/versions")
local ReleaseBehaviorTests = require("../publication/releases/tests/behavior")
local ReleasePublicationTests = require("../publication/releases/tests/publication")
local NativeCheckoutTests = require("../fabricator/tests/checkout")
local DocumentTests = require("./tests/documents")
local ProjectTests = require("../fabricator/tests/project")

--# Types

type Check = { path: string, Run: () -> () }
type Group = { name: string, checks: { Check } }

--# Helpers

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
				{ path = "ci/validation/tests/documents.luau", Run = suiteCheck(DocumentTests) },
				{ path = "ci/validation/tests/template.luau", Run = suiteCheck(TemplateTests) },
				{ path = "ci/fabricator/tests/project.luau", Run = suiteCheck(ProjectTests) },
				{ path = "ci/fabricator/tests/coverage.luau", Run = suiteCheck(CoverageTests) },
				{ path = "ci/validation/tests/activation.luau", Run = suiteCheck(ActivationTests) },
				{
					path = "ci/validation/tests/testing.luau",
					Run = suiteCheck(TestingTests),
				},
				{
					path = "ci/validation/tests/plugins.luau",
					Run = suiteCheck(PluginTests),
				},
				{
					path = "ci/validation/tests/workshop.luau",
					Run = suiteCheck(WorkshopTests),
				},
				{
					path = "ci/fabricator/tests/targets.luau",
					Run = suiteCheck(TargetTests),
				},
				{
					path = "ci/fabricator/tests/discovery.luau",
					Run = suiteCheck(DiscoveryTests),
				},
				{
					path = "ci/validation/tests/providers.luau",
					Run = suiteCheck(ProviderTests),
				},
				{ path = "ci/validation/policy.luau", Run = Policy.Run },
				{ path = "ci/validation/tests/policy.luau", Run = PolicyTests.Run },
				{ path = "ci/validation/tests/canonical.luau", Run = CanonicalTests.Run },
				{ path = "ci/validation/repository.luau", Run = Repository.Run },
				{ path = "ci/publication/releases/validate.luau", Run = ReleaseValidation.Run },
				{
					path = "ci/validation/tests/config.luau",
					Run = suiteCheck(ConfigTests),
				},
				{
					path = "ci/validation/tests/catalogue.luau",
					Run = suiteCheck(CatalogueTests),
				},
				{ path = "ci/validation/tests/artifacts.luau", Run = ArtifactTests.Run },
				{
					path = "ci/validation/tests/rules.luau",
					Run = suiteCheck(RuleTests),
				},
				{
					path = "ci/validation/tests/gate.luau",
					Run = suiteCheck(GateTests),
				},
			},
		},
		{
			name = "Workflow rules",
			checks = {
				{ path = "ci/validation/workflows.luau", Run = WorkflowValidation.Run },
				{ path = "ci/validation/tests/workflows.luau", Run = suiteCheck(WorkflowTests) },
			},
		},
		{
			name = "Access policy",
			checks = {
				{ path = "ci/security/access/tests/policy.luau", Run = AccessTests.Run },
				{ path = "ci/security/access/tests/publication.luau", Run = PublicationTests.Run },
				{ path = "ci/integration/tests/config.luau", Run = ControlTests.Run },
				{ path = "ci/integration/tests/source-approval.luau", Run = SourceApprovalTests.Run },
				{ path = "ci/integration/tests/source-promotion.luau", Run = suiteCheck(SourcePromotionTests) },
				{ path = "ci/integration/tests/request.luau", Run = RequestTests.Run },
				{ path = "ci/integration/tests/modules.luau", Run = ModuleTests.Run },
			},
		},
		{
			name = "Receipts",
			checks = {
				{ path = "ci/security/receipts/tests/authentication.luau", Run = ReceiptAuthenticationTests.Run },
				{
					path = "ci/security/receipts/tests",
					Run = function()
						ReceiptBundleTests:Run(function(report)
							table.insert(suiteReports, report)
						end)
					end,
				},
			},
		},
		{
			name = "Release tooling",
			checks = {
				{
					path = "ci/publication/releases/tests",
					Run = function()
						VersionTests:Run(function(report)
							table.insert(suiteReports, report)
						end)
						ReleaseBehaviorTests:Run(function(report)
							table.insert(suiteReports, report)
						end)
						ReleasePublicationTests:Run(function(report)
							table.insert(suiteReports, report)
						end)
						NativeCheckoutTests:Run(function(report)
							table.insert(suiteReports, report)
						end)
					end,
				},
			},
		},
	}
	local evidence = {
		suites = suiteReports,

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
