-- ci/integration/tests/modules.luau
--!strict

local ModuleTests = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Policy = require("../../validation/policy")
local Rules = require("../../libraries/registry/rules")
local VerifyRepository = require("../../publication/repo/verify")

--# Helpers

local function probe(source: string, env: { [string]: string }?)
	local path = "build/validation/probe-" .. tostring(math.random(1, 1000000000)) .. ".luau"
	Fs.writeDir("build/validation")
	Fs.writeFile(path, "-- Generated module test.\n" .. source)
	local options: Process.ExecutionOptions = { env = env }
	local success, result = pcall(Process.exec, "lune", { "run", path }, options)
	Fs.removeFile(path)
	assert(success, tostring(result))
	assert(result.ok, result.stderr)
	assert(result.stdout == "", "module execution logged instead of returning")
end

--# Functions

function ModuleTests.Run()
	local definition = Policy.Read()
	local lines = {}
	local sentinels = {}

	for _, root in { "build/tests/artifacts", "build/tests/rules" } do
		Fs.writeDir(root)
		local sentinel = root .. "/import-preserved"
		Fs.writeFile(sentinel, "preserved")
		table.insert(sentinels, sentinel)
	end

	local success, failure = pcall(function()
		for _, file in Policy.CheckRepository(definition) do
			table.insert(
				lines,
				"do\nlocal subject = require("
					.. Serde.encode("json", "../../" .. file:sub(1, -6))
					.. ")\nassert(type(subject) == 'table')"
			)

			if not Policy.IsLibrary(file, definition) then
				table.insert(lines, "assert(type(subject.Run) == 'function')")
			end

			table.insert(lines, "end")
		end

		probe(table.concat(lines, "\n"), { RESULTS = "", ENABLED = "", RUNNER_TEMP = "", GITHUB_PATH = "" })

		for _, path in sentinels do
			assert(Fs.readFile(path) == "preserved", "module import reset its fixture")
		end

		probe(
			[[local Repository = require("../../ci/publication/repo/build")
local Config = require("../../ci/libraries/registry/config")
local config = Config.Read()
config.repository.enabled = false
assert(not pcall(Repository.Generate, config, {source = "test", repository = "test"}))
]],
			{ RUNNER_TEMP = "", GITHUB_PATH = "", GITHUB_EVENT_NAME = "", CI_INPUT_REF = "" }
		)

		Fs.writeDir("build/repo")
		Fs.writeFile("build/repo/stale-output", "stale")
		probe([[require("../../ci/publication/repo/build").Run()]], {
			GITHUB_SHA = string.rep("a", 40),
			GITHUB_REPOSITORY = "fixture/project",
			GITHUB_EVENT_NAME = "",
			CI_INPUT_REF = "",
		})
		assert(not Fs.isFile("build/repo/stale-output"), "repository generation retained stale output")
		local publication = Rules.Entries(Serde.decode("json", Fs.readFile("build/repo/publication.json")))
		assert(
			publication.source == string.rep("a", 40) and publication.repository == "fixture/project",
			"repository identity differs"
		)

		for _, file in Fs.readDir("ci/publication/repo/templates") do
			assert(
				Fs.readFile("build/repo/" .. file) == Fs.readFile("ci/publication/repo/templates/" .. file),
				"repository template differs"
			)
		end

		for _, raw in
			Rules.Array(
				Rules.Entries(
					Rules.Entries(Serde.decode("json", Fs.readFile("ci/publication/repo/ruleset.json"))).publication
				).cases
			)
		do
			local case = Rules.Entries(raw)
			local source = case.source
			local repository = case.repository
			assert(source == nil or type(source) == "string", "invalid publication source fixture")
			assert(repository == nil or type(repository) == "string", "invalid publication repository fixture")
			local accepted = pcall(VerifyRepository.Check, case.record, source, repository)
			assert(accepted == case.valid, "publication identity case: " .. tostring(case.name))
		end
	end)

	for _, path in sentinels do
		if Fs.isFile(path) then
			Fs.removeFile(path)
		end
	end

	assert(success, tostring(failure))
end

return ModuleTests
