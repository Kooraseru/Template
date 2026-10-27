-- ci/preflight/planBuilder.luau
--!strict

local Fs = require("@lune/fs")
local Contract = require("@ci/bootstrap/contract")
local Discovery = require("@ci/bootstrap/discovery")
local Planner = require("@ci/bootstrap/planning")
local Contracts = require("./contracts")

local PlanBuilder = {}
PlanBuilder.__index = PlanBuilder

export type Plan = {
	tasks: { Contract.Task },
	available: boolean,
	diagnostics: { Contracts.Diagnostic },
}

type Fields = { discovery: Discovery.Discovery, planner: Planner.Planner }

export type PlanBuilder = setmetatable<Fields, typeof(PlanBuilder)>

local function failureLocation(message: string): (string, number)
	local path = message:match("^([^:]+%.toml):") or message:match("^([^:]+%.luau):")
	local identity = message:match("^([%w_-]+):") or message:match("^output collision: ([%w_-]+)")
	if not path and identity then
		path = `ci/components/{identity}/component.toml`
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
		for line in Fs.readFile(path):gmatch("[^\r\n]+") do
			lineNumber += 1
			if line:match(`^%s*{field}%s*=`) then
				return path, lineNumber
			end
		end
	end
	return path, 1
end

function PlanBuilder.new(): PlanBuilder
	local fields: Fields = { discovery = Discovery.new(), planner = Planner.new() }
	return setmetatable(fields, PlanBuilder)
end

function PlanBuilder.Build(self: PlanBuilder, event: string): Plan
	local built, tasks = xpcall(function(): { Contract.Task }
		local components = self.discovery:Discover()
		return self.planner:Resolve(components, event)
	end, tostring)
	if built then
		return { tasks = tasks, available = true, diagnostics = {} }
	end
	local message = tostring(tasks)
	local path, line = failureLocation(message)
	return {
		tasks = {},
		available = false,
		diagnostics = {
			{
				path = path,
				line = line,
				column = 1,
				endColumn = 2,
				severity = "error",
				message = message,
			},
		},
	}
end

return PlanBuilder
