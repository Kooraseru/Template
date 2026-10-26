-- ci/bootstrap/planning.luau
--!strict

local Contract = require("./contract")
local Glob = require("./glob")

local Planner = {}
Planner.__index = Planner

export type Planner = setmetatable<{}, typeof(Planner)>

function Planner.new(): Planner
	local fields = {}
	return setmetatable(fields, Planner)
end

-- Source hosts are discovered by their owning source/hosts extension point.
-- Bootstrap does not define or enumerate supported platforms.
const RESERVED_OUTPUTS: { string } = {
	"ci/bootstrap/**",
	".github/workflows/**",
	".git/**",
}

local function fail(message: string): never
	error(message, 0)
end

local function names<T>(dictionary: { [string]: T }): { string }
	local result: { string } = {}
	for name in dictionary do
		table.insert(result, name)
	end
	table.sort(result)
	return result
end

-- Sort once per discovery: consumers and providers remain deterministic even
-- when filesystem enumeration order differs across operating systems.
local function orderByDependencies(active: { [string]: Contract.Contract }, dependencies: { [string]: { [string]: boolean } }): { string }
	local degree: { [string]: number } = {}
	local successors: { [string]: { string } } = {}
	for identity in active do
		degree[identity] = 0
		successors[identity] = {}
	end

	for identity, required in dependencies do
		for dependency in required do
			degree[identity] += 1
			table.insert(successors[dependency], identity)
		end
	end

	local queue: { string } = {}
	for identity, count in degree do
		if count == 0 then
			table.insert(queue, identity)
		end
	end
	table.sort(queue)

	local ordered: { string } = {}
	while #queue > 0 do
		local identity = queue[1]
		if not identity then
			break
		end
		table.remove(queue, 1)
		table.insert(ordered, identity)
		for _, successor in successors[identity] do
			degree[successor] -= 1
			if degree[successor] == 0 then
				table.insert(queue, successor)
			end
		end
		table.sort(queue)
	end

	if #ordered ~= #names(active) then
		local involved: { string } = {}
		for identity, count in degree do
			if count > 0 then
				table.insert(involved, identity)
			end
		end
		table.sort(involved)
		fail(`dependency cycle involving: {table.concat(involved, ", ")}`)
	end
	return ordered
end

-- Glob output ownership is checked before any code runs. Exact-path checks
-- would miss collisions such as build/*.bin with build/out.bin.
local function resolveOutputs(active: { [string]: Contract.Contract }): ()
	local ownership: { { identity: string, path: string } } = {}
	for _, identity in names(active) do
		for _, output in active[identity].outputs do
			for _, reserved in RESERVED_OUTPUTS do
				if Glob.Overlaps(output, reserved) then
					fail(`{identity}: output glob intersects protected source path {reserved}`)
				end
			end
			for _, owner in ownership do
				if Glob.Overlaps(output, owner.path) then
					fail(`output collision: {owner.identity} ({owner.path}) and {identity} ({output})`)
				end
			end
			table.insert(ownership, { identity = identity, path = output })
		end
	end
end

local function requireBoundary(component: Contract.Contract): ()
	if component.boundary ~= "read" then
		fail(`{component.identity}: privileged execution requires a separately authorized GitHub job`)
	end
end

function Planner.Resolve(self: Planner, components: { Contract.Contract }, event: string): { Contract.Task }
	local supportedEvents: { [string]: boolean } = {
		push = true,
		pull_request = true,
		workflow_dispatch = true,
	}
	if not supportedEvents[event] then
		fail(`unsupported GitHub event: {event}`)
	end

	local active: { [string]: Contract.Contract } = {}
	for _, component in components do
		if component.enabled then
			active[component.identity] = component
		end
	end

	local providers: { [string]: string } = {}
	for _, identity in names(active) do
		for _, capability in active[identity].provides do
			if providers[capability] then
				fail(`duplicate provider for {capability}: {providers[capability]} and {identity}`)
			end
			providers[capability] = identity
		end
	end

	local dependencies: { [string]: { [string]: boolean } } = {}
	for _, identity in names(active) do
		local dependenciesForComponent: { [string]: boolean } = {}
		for _, capability in active[identity].requires do
			local provider = providers[capability]
			if not provider then
				fail(`{identity}: missing required capability {capability}`)
			end
			dependenciesForComponent[provider] = true
		end
		dependencies[identity] = dependenciesForComponent
	end

	resolveOutputs(active)
	local ordered = orderByDependencies(active, dependencies)
	local selected: { [string]: boolean } = {}
	for _, identity in ordered do
		if active[identity]:SupportsEvent(event) then
			selected[identity] = true
		end
	end
	for identity in selected do
		for required in dependencies[identity] do
			if not selected[required] then
				fail(`{identity}: required provider {required} is not available for {event}`)
			end
		end
	end

	local tasks: { Contract.Task } = {}
	for _, identity in ordered do
		if selected[identity] then
			local component = active[identity]
			requireBoundary(component)
			local required: { string } = {}
			for provider in dependencies[identity] do
				table.insert(required, provider)
			end
			table.sort(required)

			table.insert(tasks, component:ToTask(required))
		end
	end

	return tasks
end

return Planner
