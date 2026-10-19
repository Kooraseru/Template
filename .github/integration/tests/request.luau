-- .github/integration/tests/request.luau
--!strict

local RequestTests = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../../../libraries/registry/rules")
local Files = require("../../../libraries/bootstrap/files")
local Request = require("../request")
local Gate = require("../gate")
local Publication = require("../publication")
local PendingReceipt = require("../pending-receipt")
local RefreshPRs = require("../refresh-prs")
local ConfigureEditor = require("../configure-editor")

--# Functions

function RequestTests.Run()
	local document = Rules.Entries(Serde.decode("json", Fs.readFile(".github/integration/ruleset.json")))
	local definition = Rules.Entries(document.request)
	local options =
		Rules.Entries(Rules.Entries(Serde.decode("json", Fs.readFile(".github/integration/ruleset.json"))).controls)
	local count = 0
	local dropdowns = 0

	for key, raw in options do
		assert(type(key) == "string", "invalid control name")
		local option = Rules.Entries(raw)
		count += 1

		if not option.type then
			dropdowns += 1
		end

		for _, choice in Rules.Array(option.options or {}) do
			assert(Request.Normalize({ [key] = choice })[key] == choice, "dropdown option rejected")
		end
	end

	assert(count == 14 and dropdowns == 12, "manual control catalogue changed")
	assert(Request.Normalize({}, false).operation == "Full Run", "automatic run must select full pipeline")

	for _, raw in Rules.Array(definition.cases) do
		local case = Rules.Entries(raw)
		local success = pcall(function()
			return Request.Normalize(case.inputs)
		end)
		assert(success == case.valid, "request case: " .. tostring(case.name))
	end

	for _, raw in Rules.Array(definition.prs) do
		local case = Rules.Entries(raw)
		assert(type(case.input) == "string", "invalid PR fixture")
		local success, result = pcall(Request.ParsePR, case.input)
		assert(success == case.valid and (not success or result == case.expected), "PR parsing case: " .. case.input)
	end

	assert(not Request.Diagnostic(Request.Normalize({})), "default selection is diagnostic")

	for _, inputs in Rules.Array(definition.diagnostics) do
		assert(Request.Diagnostic(Request.Normalize(inputs)), "partial selection must be diagnostic")
	end

	local root = "build/tests/request"
	Files.Reset(root)
	local success, failure = pcall(function()
		local event = root .. "/event.json"
		Fs.writeFile(event, Serde.encode("json", { inputs = { operation = "Full Run" } }))
		local env: Request.Environment = {
			GITHUB_EVENT_PATH = event,
			GITHUB_EVENT_NAME = "workflow_dispatch",
			GITHUB_ACTIONS = "true",
			GITHUB_SERVER_URL = "https://github.com",
			GITHUB_REF = "refs/heads/source",
			GITHUB_ACTOR = "admin",
			GITHUB_RUN_ID = "123",
			GITHUB_SHA = string.rep("a", 40),
			CI_PUBLICATION_JOB = "true",
		}
		local run = { id = 123, head_sha = env.GITHUB_SHA, status = "in_progress", actor = { login = "admin" } }
		assert(PendingReceipt.Allowed(run, env), "originating run receipt rejected")
		local push = table.clone(env)
		push.GITHUB_EVENT_NAME = "push"
		assert(PendingReceipt.Allowed(run, push), "source push receipt rejected")

		for _, raw in Rules.Array(definition.pending) do
			local selected = table.clone(env)

			for key, value in Rules.Entries(raw) do
				assert(type(key) == "string" and type(value) == "string", "invalid pending receipt fixture")
				selected[key] = value
			end

			assert(not PendingReceipt.Allowed(run, selected), "foreign or untrusted pending receipt accepted")
		end

		assert(
			not PendingReceipt.Allowed(
				{ id = 123, head_sha = env.GITHUB_SHA, status = "completed", conclusion = "failure", actor = run.actor },
				env
			),
			"failed completed receipt accepted"
		)
		Fs.writeFile(event, Serde.encode("json", { inputs = { operation = "Publish" } }))
		assert(
			Publication.Authorize(env, function()
				return true
			end),
			"administrator publication denied"
		)
		assert(not pcall(function()
			Publication.Authorize(env, function()
				return false
			end)
		end), "contributor publication accepted")

		for _, patch in { { ACT = "true" }, { GITHUB_REF = "refs/heads/other" } } do
			local selected = table.clone(env)

			for key, value in patch do
				selected[key] = value
			end

			assert(not pcall(function()
				Publication.Authorize(selected, function()
					return true
				end)
			end), "untrusted publication accepted")
		end

		Fs.writeFile(event, Serde.encode("json", { inputs = { operation = "Build" } }))
		assert(not pcall(function()
			Publication.Authorize(env, function()
				return true
			end)
		end), "build-only publication accepted")
		local controls = Request.Normalize({ operation = "Build", build_targets = "Linux" })
		Fs.writeFile(event, Serde.encode("json", { inputs = controls }))
		env.CI_PUBLICATION_JOB = nil
		assert(Request.DiagnosticReuseAllowed({ controls = controls }, env), "matching diagnostic receipt rejected")
		local other = table.clone(controls)
		other.validation_scope = "Receipts"
		assert(not Request.DiagnosticReuseAllowed({ controls = other }, env), "mismatched diagnostic receipt accepted")
		env.CI_PUBLICATION_JOB = "true"
		assert(
			not Request.DiagnosticReuseAllowed({ controls = controls }, env),
			"diagnostic receipt authorized publication"
		)
		Fs.writeFile(event, Serde.encode("json", { inputs = {} }))
		env.CI_PUBLICATION_JOB = nil
		assert(not Request.DiagnosticReuseAllowed({ controls = controls }, env), "full run reused diagnostic receipt")
	end)
	Files.Reset(root)
	assert(success, tostring(failure))

	for _, raw in Rules.Array(definition.gates) do
		local case = Rules.Entries(raw)
		assert(type(case.policy) == "string", "missing gate policy")
		local controls = Request.Normalize(
			if case.source then {} else { operation = "Build", gate_policy = case.policy },
			not case.source
		)
		local results: Rules.Dictionary = {
			validate = { result = "success" },
			build = { result = case.build or "success" },
			["validation-receipt"] = { result = case.receipt or "success" },
		}

		for _, name in { "repository", "pages", "images", "release" } do
			results[name] = { result = "skipped" }
		end

		local errors = Gate.Check(
			controls,
			results,
			{ repository = "false", pages = "false", images = "false", release = "false" },
			{
				validation = { success = case.validation },
				context = if case.source
					then { source_authorization = { kind = "admin-source-push", actor = "admin" } }
					else {},
			},
			if case.source then "push" else "workflow_dispatch"
		)
		assert((#errors == 0) == case.valid, "gate behavior: " .. tostring(case.name))

		if type(case.error) == "string" then
			assert(table.concat(errors, "; "):find(case.error, 1, true), "missing administrator routing diagnostic")
		end
	end

	local before =
		'prefix\n        # BEGIN GENERATED PR CHOICES\n        options: ["Source"]\n        # END GENERATED PR CHOICES\nsuffix\n'
	local after = RefreshPRs.RenderChoices(before, definition.pulls)
	assert(
		after:sub(1, 7) == "prefix\n" and after:sub(-8) == "\nsuffix\n",
		"dropdown changed outside generated markers"
	)
	local newest = assert((after:find("#9", 1, true)))
	local older = assert((after:find("#2", 1, true)))
	assert(
		newest < older and after:find('\\"quote\\"', 1, true) and not after:find("#3", 1, true),
		"dropdown ordering or escaping failed"
	)
	assert(RefreshPRs.RenderChoices(after, definition.pulls) == after, "dropdown refresh is not idempotent")
	assert(not pcall(RefreshPRs.RenderChoices, "missing", definition.pulls), "missing dropdown markers accepted")
	assert(
		not RefreshPRs.RenderChoices(before, { { number = 1, title = "${{ secrets.EXAMPLE }}" } }):find("${{", 1, true),
		"workflow expression injection"
	)
	local merged = ConfigureEditor.Merge(
		{ ["act.command"] = "local", ["[luau]"] = { custom = true } },
		{ ["[luau]"] = { formatter = "stylua" } }
	)
	assert(
		merged["act.command"] == "local"
			and Rules.Entries(merged["[luau]"]).custom == true
			and Rules.Entries(merged["[luau]"]).formatter == "stylua",
		"editor merge discarded local settings"
	)
end

return RequestTests
