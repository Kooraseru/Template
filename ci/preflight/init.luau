-- ci/preflight/init.luau
--!strict

-- Preflight derives diagnostics from the exact discovered CI plan.
local Fs = require("@lune/fs")
local Contract = require("./bootstrap/contract")
local Discovery = require("./bootstrap/discovery")
local Planner = require("./bootstrap/planning")
local Analyzer = require("@self/analyzer")

local Preflight = {}
Preflight.__index = Preflight

export type Result = {
	tasks: { Contract.Task },
	analysis: Analyzer.Result?,
	passed: boolean,
}

type PlanOutcome = {
	tasks: { Contract.Task }?,
	failure: string?,
}

type Fields = {
	discovery: Discovery.Discovery,
	planner: Planner.Planner,
	analyzer: Analyzer.Analyzer,
}

export type Preflight = setmetatable<Fields, typeof(Preflight)>

local function failureLocation(message: string): (string, number)
	local path = message:match("^([^:]+%.luau):")
	local identity = message:match("^([%w_-]+):") or message:match("^output collision: ([%w_-]+)")
	if not path and identity then
		path = `ci/components/{identity}/init.luau`
	end
	path = path or "ci/bootstrap/planning.luau"

	local field: string? = nil
	if message:find("required capability", 1, true) or message:find("dependency cycle", 1, true) then
		field = "requires"
	elseif message:find("provider", 1, true) then
		field = "provides"
	elseif message:find("output", 1, true) then
		field = "outputs"
	elseif message:find("input", 1, true) then
		field = "inputs"
	end

	if field and Fs.isFile(path) then
		local lineNumber = 0
		local contents = Fs.readFile(path)
		for line in contents:gmatch("[^\r\n]+") do
			lineNumber += 1
			if line:match(`^%s*{field}%s*=`) then
				return path, lineNumber
			end
		end
	end
	return path, 1
end

function Preflight.new(): Preflight
	local fields: Fields = {
		discovery = Discovery.new(),
		planner = Planner.new(),
		analyzer = Analyzer.new(),
	}
	return setmetatable(fields, Preflight)
end

function Preflight.Run(self: Preflight, event: string): Result
	local planned, outcome = xpcall(function(): PlanOutcome
		local components = self.discovery:Discover()
		return { tasks = self.planner:Resolve(components, event) }
	end, function(problem: unknown): PlanOutcome
		return { failure = tostring(problem) }
	end)

	if not planned then
		local message = outcome.failure or "unable to construct the CI plan"
		local path, line = failureLocation(message)
		print(`{path}:{line}:1:2: error: {message}`)
		return { tasks = {}, analysis = nil, passed = false }
	end

	local tasks = outcome.tasks
	if not tasks then
		print("ci/bootstrap/planning.luau:1:1:2: error: planner returned no execution tasks")
		return { tasks = {}, analysis = nil, passed = false }
	end
	local analysis = self.analyzer:Analyze(tasks)
	for _, diagnostic in analysis.diagnostics do
		print(
			`{diagnostic.path}:{diagnostic.line}:{diagnostic.column}:{diagnostic.endColumn}: {diagnostic.severity}: {diagnostic.message}`
		)
	end
	if #analysis.diagnostics == 0 then
		print("Preflight: no statically detectable blockers in the planned CI path.")
	end
	return { tasks = tasks, analysis = analysis, passed = analysis.passed }
end

return Preflight
