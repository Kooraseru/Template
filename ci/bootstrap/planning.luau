-- ci/bootstrap/planning.luau
--!strict

local Component = require("./component")
local Glob = require("./glob")

local Planning = {}

-- Source hosts are discovered by their owning source/hosts extension point.
-- Bootstrap does not define or enumerate supported platforms.
local RESERVED_OUTPUTS = {
	"ci/bootstrap/**",
	".github/workflows/**",
	".git/**",
}

local function fail(message: string): never
	error(message, 0)
end

local function names(dictionary): { string }
	local result = {}
	for name in dictionary do
		table.insert(result, name)
	end
	table.sort(result)
	return result
end

-- Sort once per discovery: consumers and providers remain deterministic even
-- when filesystem enumeration order differs across operating systems.
local function orderByDependencies(active, dependencies): { string }
	local degree = {}
	local successors = {}
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

	local queue = {}
	for identity, count in degree do
		if count == 0 then
			table.insert(queue, identity)
		end
	end
	table.sort(queue)

	local ordered = {}
	while #queue > 0 do
		local identity = table.remove(queue, 1)
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
		local involved = {}
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
local function resolveOutputs(active)
	local ownership = {}
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

local function requireBoundary(component)
	if component.boundary ~= "read" then
		fail(`{component.identity}: privileged execution requires a separately authorized GitHub job`)
	end
end

function Planning.Resolve(components: { Component.Component }, event: string)
	local supportedEvents = { push = true, pull_request = true, workflow_dispatch = true }
	if not supportedEvents[event] then
		fail(`unsupported GitHub event: {event}`)
	end

	local active = {}
	for _, component in components do
		if component.enabled then
			active[component.identity] = component
		end
	end

	local providers = {}
	for _, identity in names(active) do
		for _, capability in active[identity].provides do
			if providers[capability] then
				fail(`duplicate provider for {capability}: {providers[capability]} and {identity}`)
			end
			providers[capability] = identity
		end
	end

	local dependencies = {}
	for _, identity in names(active) do
		local dependenciesForComponent = {}
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
	local selected = {}
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

	local validators = {}
	local workers = {}
	for identity in selected do
		local component = active[identity]
		requireBoundary(component)
		if component:IsValidator() then
			validators[identity] = true
		else
			workers[identity] = true
		end
	end


	-- Planning-stage validators cannot depend on code that runs only after
	-- validation. Work tasks may depend on validators because that phase is first.
	for identity in validators do
		for required in dependencies[identity] do
			if not validators[required] then
				fail(`{identity}: validator depends on a worker {required}`)
			end
		end
	end

	local validationTasks = {}
	local workTasks = {}
	for _, identity in ordered do
		if not selected[identity] then
			continue
		end
		local required = {}
		for provider in dependencies[identity] do
			table.insert(required, provider)
		end
		table.sort(required)

		local task = active[identity]:ToTask(required)
		if validators[identity] then
			table.insert(validationTasks, task)
		else
			table.insert(workTasks, task)
		end
	end

	return validationTasks, workTasks
end

return Planning
