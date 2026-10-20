-- .github/integration/gate.luau
--!strict

local Gate = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Request = require("./request")
local Rules = require("../../libraries/registry/rules")

--# Functions

function Gate.Check(
	controls: Request.Controls,
	rawResults: unknown,
	rawEnabled: unknown,
	rawPlan: unknown,
	event: string?
): { string }
	local results = Rules.Entries(rawResults)
	local enabled = Rules.Entries(rawEnabled)
	local plan = Rules.Entries(rawPlan)
	local errors = {}
	local validation = Rules.Entries(plan.validation or {})
	local context = Rules.Entries(plan.context or {})

	if Rules.Entries(results.validate).result ~= "success" then
		table.insert(errors, "Input authorization or planning failed")
	end

	if validation.success == false and not Request.IgnoresValidation(controls) then
		table.insert(errors, "Selected validation checks failed")
	end

	if controls.operation ~= "Validate" then
		local build = Rules.Entries(results.build).result

		if
			build ~= "success" and not (context["local"] == true and plan.local_executing == 0 and build == "skipped")
		then
			table.insert(
				errors,
				if build ~= "skipped"
					then "Build or verified output restoration failed"
					elseif
						context.source_authorization
					then "Administrator-approved source run skipped required builds; check job routing"
					else "No administrator execution approval or matching stored builds were found"
			)
		end

		for _, name in { "repository", "pages", "release", "images" } do
			if enabled[name] == "true" and Rules.Entries(results[name]).result ~= "success" then
				table.insert(errors, name .. " did not succeed")
			end
		end

		if
			context["local"] ~= true
			and (event == "workflow_dispatch" or context.source_authorization)
			and not Request.IgnoresCoverage(controls)
			and Rules.Entries(results["validation-receipt"]).result ~= "success"
		then
			table.insert(errors, "Required receipt coverage is missing")
		end
	end

	return errors
end

function Gate.Run()
	local controls = Request.Read()
	local path = "build/tmp/releases/plan.json"
	local plan = Rules.Entries(if Fs.isFile(path) then Serde.decode("json", Fs.readFile(path)) else {})
	local errors = Gate.Check(
		controls,
		Serde.decode("json", assert(Process.env.RESULTS, "missing results")),
		Serde.decode("json", assert(Process.env.ENABLED, "missing enabled stages")),
		plan,
		Process.env.GITHUB_EVENT_NAME
	)
	local summary = Process.env.GITHUB_STEP_SUMMARY

	if summary and summary ~= "" then
		local approval = Rules.Entries(Rules.Entries(plan.context or {}).source_authorization or {})
		local text = "## Gate\n\nPolicy: " .. controls.gate_policy .. "\n\n"

		if approval.kind then
			text ..= "Source approval: " .. tostring(approval.kind) .. " by " .. tostring(approval.actor) .. ".\n\n"
		end

		local skipped = Rules.Array(plan.local_skipped or {})
		if #skipped > 0 then
			text ..= "Unverified local targets:\n\n"
			for _, raw in skipped do
				local target = Rules.Entries(raw)
				text ..= "- " .. tostring(target.name) .. ": " .. tostring(target.reason) .. "\n"
			end
			text ..= "\n"
		end
		text ..= if #errors > 0
			then table.concat(errors, "\n\n")
			else "Selected executable stages completed; unverified targets are not passes."
		Fs.writeFile(summary, (if Fs.isFile(summary) then Fs.readFile(summary) else "") .. text .. "\n")
	end

	assert(#errors == 0, table.concat(errors, "; "))
end

return Gate
