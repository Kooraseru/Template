-- .github/integration/request.luau
--!strict

local Request = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Rules = require("../../libraries/registry/rules")

--# Types

export type Controls = { [string]: string }
export type Environment = { [string]: string? }

type PullRequest = { number: number, title: string }

--# Helpers

local function digits(value: string): boolean
	return value:match("^%d+$") ~= nil and (value == "0" or value:sub(1, 1) ~= "0")
end

--# Functions

function Request.Version(version: string): { version: string, prerelease: boolean, type: string }
	local main, pre = version:match("^(.-)%-pre%.(%d+)$")
	local major, minor, patch = (main or version):match("^(%d+)%.(%d+)%.(%d+)$")
	assert(
		major and minor and patch and digits(major) and digits(minor) and digits(patch) and (not pre or digits(pre)),
		"Version must be MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-pre.N without leading zeroes"
	)

	return { version = version, prerelease = pre ~= nil, type = if pre then "Pre-Release" else "Release" }
end

function Request.PullRequestLabel(pr: PullRequest): string
	assert(pr.number > 0 and pr.number % 1 == 0 and pr.number <= 9007199254740991, "Invalid PR identity")
	local title = pr.title:gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	title = title:gsub("%${{", "$ { {"):sub(1, 100)

	return "#" .. tostring(pr.number) .. " " .. title
end

function Request.ParsePR(value: string?): number
	if value == nil or value == "Source" then
		return 0
	end

	local identity = value:match("^#([1-9]%d*)$") or value:match("^#([1-9]%d*) .*$")
	local number = if identity then tonumber(identity) else nil
	assert(number and number <= 9007199254740991, "Select Source or a pull request from the dropdown")

	return number
end

function Request.Normalize(raw: unknown, manual: boolean?): Controls
	local definitions =
		Rules.Entries(Rules.Entries(Serde.decode("json", Fs.readFile(".github/integration/ruleset.json"))).controls)
	local catalogue = Rules.Entries(Serde.decode("json", Fs.readFile("fabricator/targets.json")))
	local inputs = Rules.Entries(raw or {})
	local controls: Controls = {}

	for key in inputs do
		assert(definitions[key] ~= nil, "Unknown CI setting")
	end

	for key, rawDefinition in definitions do
		assert(type(key) == "string", "Invalid control name")
		local definition = Rules.Entries(rawDefinition)
		local value = if inputs[key] ~= nil then inputs[key] else definition.default
		assert(type(value) == "string", "Invalid " .. key)

		if definition.type ~= "string" then
			if key == "pull_request" then
				Request.ParsePR(value)
			else
				local accepted = table.find(Rules.Array(definition.options), value) ~= nil

				if key == "build_targets" then
					for _, target in Rules.Array(catalogue.targets) do
						accepted = accepted or Rules.Entries(target).name == value
					end
				end

				assert(accepted, "Unknown " .. key .. ": " .. value)
			end
		end

		controls[key] = value
	end

	if manual == false then
		controls.operation = "Full Run"
	end

	local pr = Request.ParsePR(controls.pull_request)
	assert(
		pr == 0 or (controls.operation ~= "Publish" and controls.operation ~= "Full Run"),
		"Publication requires Source; select Validate or Build for a PR"
	)
	assert(
		controls.operation ~= "Publish" or not controls.cache_policy:match("^Rebuild"),
		"Publish cannot rebuild; select Full Run"
	)
	assert(
		(controls.release_version ~= "") == (controls.release_commit ~= ""),
		"Release version and source commit must be supplied together"
	)

	if controls.release_version ~= "" then
		local version = Request.Version(controls.release_version)
		assert(
			#controls.release_commit == 40 and controls.release_commit:match("^[a-f0-9]+$"),
			"Release source commit must be a full 40-character SHA"
		)
		assert(pr == 0, "Explicit public version selection requires Source")
		assert(
			not controls.release_output:match("^Publish ") or controls.release_output == "Publish " .. version.type,
			"Release output type does not match the selected SemVer version"
		)
	end

	return controls
end

function Request.Read(env: Environment?): Controls
	local selected = env or Process.env
	local inputs: unknown = {}

	if selected.GITHUB_EVENT_PATH and selected.GITHUB_EVENT_PATH ~= "" then
		inputs = Rules.Entries(Serde.decode("json", Fs.readFile(selected.GITHUB_EVENT_PATH))).inputs or {}
	end

	local manual = selected.GITHUB_EVENT_NAME == "workflow_dispatch"

	return Request.Normalize(if manual then inputs else {}, manual)
end

function Request.IgnoresValidation(controls: Controls): boolean
	return controls.gate_policy == "Ignore validation failures" or controls.gate_policy == "Ignore both"
end

function Request.IgnoresCoverage(controls: Controls): boolean
	return controls.gate_policy == "Ignore incomplete coverage" or controls.gate_policy == "Ignore both"
end

function Request.Diagnostic(controls: Controls): boolean
	return controls.validation_scope ~= "All"
		or controls.gate_policy ~= "Enforce all"
		or controls.build_targets ~= "Configured"
		or controls.compiler ~= "Any"
		or controls.architecture ~= "Any"
end

function Request.DiagnosticReuseAllowed(receipt: unknown, env: Environment?): boolean
	local selected = env or Process.env

	if selected.CI_PUBLICATION_JOB == "true" or selected.GITHUB_EVENT_NAME ~= "workflow_dispatch" then
		return false
	end

	local controls = Request.Read(selected)
	local stored = Rules.Entries(receipt).controls

	if not Request.Diagnostic(controls) or type(stored) ~= "table" then
		return false
	end

	local previous = Rules.Entries(stored)

	for _, key in { "validation_scope", "build_targets", "compiler", "architecture", "gate_policy" } do
		if previous[key] ~= controls[key] then
			return false
		end
	end

	return true
end

return Request
