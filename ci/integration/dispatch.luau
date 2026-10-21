-- ci/integration/dispatch.luau
--!strict

local Dispatch = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Request = require("./request")
local GitHub = require("../libraries/bootstrap/github")
local Outputs = require("../libraries/bootstrap/outputs")

--# Functions

function Dispatch.Run()
	local controls = Request.Read()
	local manual = Process.env.GITHUB_EVENT_NAME == "workflow_dispatch"
	assert(
		not manual
			or Process.env.ACT == "true"
			or Process.env.GITHUB_ACTIONS ~= "true"
			or GitHub.IsAdmin(GitHub.Actor()),
		"The manual CI control panel requires repository administrator permission"
	)
	assert(
		Process.env.ACT ~= "true" or controls.gate_policy == "Enforce all",
		"Gate overrides require hosted administrator execution"
	)

	Outputs.Write(Process.env.GITHUB_OUTPUT, {
		operation = controls.operation,
		pr = tostring(Request.ParsePR(controls.pull_request)),
		ignore_validation = tostring(manual and Request.IgnoresValidation(controls)),
		ignore_coverage = tostring(manual and Request.IgnoresCoverage(controls)),
		diagnostic = tostring(manual and Request.Diagnostic(controls)),
	})

	local summary = Process.env.GITHUB_STEP_SUMMARY

	if summary and summary ~= "" then
		local keys = {}

		for key in controls do
			table.insert(keys, key)
		end

		table.sort(keys)
		local lines = { "## CI control panel", "", "| Setting | Selection |", "| --- | --- |" }

		for _, key in keys do
			local value = controls[key]:gsub("|", "\\|"):gsub("<", "&lt;")
			table.insert(lines, "| " .. key .. " | " .. value .. " |")
		end

		Fs.writeFile(
			summary,
			(if Fs.isFile(summary) then Fs.readFile(summary) else "") .. table.concat(lines, "\n") .. "\n"
		)
	end
end

return Dispatch
