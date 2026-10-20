-- validation/tests/template.luau
--!strict

local Test = require("@testing")

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Template = require("../template")

--# Types

type Input = { Remove: string?, Replace: { [string]: string }? }

--# Helpers

local function execute(input: Input): boolean
	local result = Process.exec("git", { "ls-files", "-z" })
	assert(result.ok, "cannot inventory template fixture")
	local files: { string } = {}
	local seen: { [string]: boolean } = {}
	for path in result.stdout:gmatch("[^%z]+") do
		if not input.Remove or (path ~= input.Remove and path:sub(1, #input.Remove + 1) ~= input.Remove .. "/") then
			table.insert(files, path)
			seen[path] = true
		end
	end
	for path in input.Replace or {} do
		if not seen[path] then
			table.insert(files, path)
			seen[path] = true
		end
	end
	local findings = Template.Check(function(path)
		assert(seen[path], "missing tracked file: " .. path)
		local replacement = if input.Replace then input.Replace[path] else nil
		return replacement or Fs.readFile(path)
	end, files)
	return #findings == 0
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Independent upstream template conformance",
	Execute = execute,
	Cases = {
		{ Name = "Current template conforms", Input = {}, Expected = true },
		{
			Name = "Recursive local actions are drift",
			Input = {
				Replace = {
					[".github/actions/run-luau/action.yml"] = "runs:\n  using: composite\n  steps:\n    - uses: ./.github/actions/run-luau\n",
				},
			},
			Expected = false,
		},

		{
			Name = "Additional language source is permitted",
			Input = { Replace = { ["src/go/main.go"] = "package main" } },
			Expected = true,
		},
		{
			Name = "Application code must stay under source",
			Input = { Replace = { ["application/main.go"] = "package main" } },
			Expected = false,
		},

		{ Name = "Missing infrastructure is drift", Input = { Remove = "security/receipts" }, Expected = false },
		{
			Name = "Missing CI orchestrator is drift",
			Input = { Remove = ".github/workflows/ci.yml" },
			Expected = false,
		},
		{
			Name = "Conformance workflow may be removed",
			Input = { Remove = ".github/workflows/template.yml" },
			Expected = true,
		},
		{
			Name = "Copied downstream rules cannot override upstream rules",
			Input = { Replace = { ["validation/ruleset.json"] = "{}" } },
			Expected = true,
		},
		{
			Name = "Build controls cannot move back to repository config",
			Input = { Replace = { ["config/project.toml"] = "[build]\nrunner = 'ubuntu-latest'\n" } },
			Expected = false,
		},
		{
			Name = "Application may select its own build commands",
			Input = { Replace = { ["src/build.toml"] = "[build]\ncommands = [['my-builder', 'compile']]\n" } },
			Expected = true,
		},
		{
			Name = "Malformed application build shape is drift",
			Input = { Replace = { ["src/build.toml"] = "build = 42\n" } },
			Expected = false,
		},
		{
			Name = "Unignored build output is drift",
			Input = { Replace = { [".gitignore"] = "# No output ignore\n" } },
			Expected = false,
		},
		{
			Name = "Tracked build output is drift",
			Input = { Replace = { ["build/unwanted.txt"] = "output" } },
			Expected = false,
		},
		{
			Name = "Malformed workflow is reported",
			Input = { Replace = { [".github/workflows/ci.yml"] = "jobs: [" } },
			Expected = false,
		},
		{
			Name = "Lua infrastructure must use a returned module",
			Input = {
				Replace = { ["fabricator/workflow.luau"] = "-- fabricator/workflow.luau\n--!strict\nlocal value = 1\n" },
			},
			Expected = false,
		},
		{
			Name = "Downstream modules are inspected without execution",
			Input = {
				Replace = {
					["fabricator/workflow.luau"] = "-- fabricator/workflow.luau\n--!strict\n\nlocal Workflow = {}\n\nfunction Workflow.Run()\n    error('Downstream code must never execute during conformance')\nend\n\nreturn Workflow\n",
				},
			},
			Expected = true,
		},
	},
}

return Test.new(definition)
