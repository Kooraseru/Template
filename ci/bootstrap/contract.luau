-- ci/bootstrap/contract.luau
--!strict

-- Validated metadata for a discovered component class.

local Contract = {}
Contract.__index = Contract

--# Types

type ContractFields = {
	identity: string,
	entry: string,
	contractFile: string,
	provides: { string },
	requires: { string },
	inputs: { string },
	outputs: { string },
	events: { string },
	boundary: string,
	enabled: boolean,
}

export type Contract = setmetatable<ContractFields, typeof(Contract)>

export type Task = {
	identity: string,
	invoker: string,
	entry: string,
	contractFile: string,
	inputs: { string },
	outputs: { string },
	needs: { string },
}

const TASK_INVOKER = "ci/bootstrap/invoke.luau"

--# Constants

local EVENTS: { [string]: boolean } = { push = true, pull_request = true, workflow_dispatch = true }

--# Helpers

local function invalid(entry: string, reason: string): never
	error(`{entry}: {reason}`, 0)
end

local function strings(entry: string, field: string, value: unknown, pattern: string?): { string }
	if type(value) ~= "table" then
		return invalid(entry, `{field} must be an array`)
	end

	local items: { string } = {}
	local seen: { [string]: boolean } = {}
	local count = 0
	local maxIndex = 0
	for index, item in value do
		if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then
			return invalid(entry, `{field} must be an array`)
		end
		if type(item) ~= "string" or item == "" then
			return invalid(entry, `{field} must contain only nonempty strings`)
		end
		count += 1
		maxIndex = math.max(maxIndex, index)
		if seen[item] then
			return invalid(entry, `duplicate {field}: {item}`)
		end
		if pattern and not item:match(pattern) then
			return invalid(entry, `invalid {field}: {item}`)
		end
		seen[item] = true
		items[index] = item
	end
	if count ~= maxIndex then
		return invalid(entry, `{field} must be a contiguous array`)
	end
	return items
end

local function paths(entry: string, field: string, value: unknown): { string }
	local items = strings(entry, field, value)
	for _, path in items do
		if path:sub(1, 1) == "/" or path:find("\\", 1, true) or path:find(":", 1, true)
			or path:find("//", 1, true) or path:sub(-1) == "/" then
			invalid(entry, `unsafe {field} glob: {path}`)
		end
		for segment in path:gmatch("[^/]+") do
			if segment == "." or segment == ".." then
				invalid(entry, `unsafe {field} glob: {path}`)
			end
		end
	end
	return items
end

--# Constructor

-- This constructor validates decoded TOML before its values reach planning.
function Contract.new(identity: string, entry: string, contractFile: string, source: unknown): Contract
	if type(source) ~= "table" then
		return invalid(contractFile, "component manifest must contain a table")
	end
	local raw: { [string]: unknown } = {}
	for field, value in source do
		if type(field) ~= "string" then
			return invalid(contractFile, "manifest keys must be strings")
		end
		raw[field] = value
	end
	if identity == "init" or not identity:match("^[%a%d][%w_-]*$") then
		invalid(contractFile, `invalid component identity: {identity}`)
	end

	local provides = strings(contractFile, "provides", raw.provides, "^[a-z][a-z0-9_.:-]*$")
	if #provides == 0 then
		invalid(contractFile, "provides must not be empty")
	end

	local eventSource = raw.events
	if eventSource == nil then
		eventSource = { "push", "pull_request", "workflow_dispatch" }
	end
	local events = strings(contractFile, "events", eventSource)
	if #events == 0 then
		invalid(contractFile, "events must not be empty")
	end
	for _, event in events do
		if not EVENTS[event] then
			invalid(contractFile, `unsupported event: {event}`)
		end
	end

	local boundary = raw.boundary
	local boundaryValue: string
	if boundary == nil then
		boundaryValue = "read"
	elseif type(boundary) == "string" then
		if boundary ~= "read" and boundary ~= "privileged" then
			return invalid(contractFile, "boundary must be read or privileged")
		end
		boundaryValue = boundary
	else
		return invalid(contractFile, "boundary must be read or privileged")
	end

	local enabled = raw.enabled
	local enabledValue: boolean
	if enabled == nil then
		enabledValue = true
	elseif type(enabled) == "boolean" then
		enabledValue = enabled
	else
		return invalid(contractFile, "enabled must be boolean")
	end

	local requirements = raw.requires
	if requirements == nil then
		requirements = {}
	end
	local inputPatterns = raw.inputs
	if inputPatterns == nil then
		inputPatterns = {}
	end
	local outputPatterns = raw.outputs
	if outputPatterns == nil then
		outputPatterns = {}
	end

	local fields: ContractFields = {
		identity = identity,
		entry = entry,
		contractFile = contractFile,
		provides = provides,
		requires = strings(contractFile, "requires", requirements, "^[a-z][a-z0-9_.:-]*$"),
		inputs = paths(contractFile, "inputs", inputPatterns),
		outputs = paths(contractFile, "outputs", outputPatterns),
		events = events,
		boundary = boundaryValue,
		enabled = enabledValue,
	}
	local allowedFields: { [string]: boolean } = {
		provides = true,
		requires = true,
		inputs = true,
		outputs = true,
		events = true,
		boundary = true,
		enabled = true,
	}
	for field in raw do
		if not allowedFields[field] then
			invalid(contractFile, `unknown or reserved contract field: {field}`)
		end
	end

	return setmetatable(fields, Contract)
end

--# Methods

function Contract.SupportsEvent(self: Contract, event: string): boolean
	return table.find(self.events, event) ~= nil
end

-- Convert a validated instance to the minimum serializable execution record.
-- Method tables and other local state never cross the artifact boundary.
function Contract.ToTask(self: Contract, needs: { string }): Task
	return {
		identity = self.identity,
		invoker = TASK_INVOKER,
		entry = self.entry,
		contractFile = self.contractFile,
		inputs = self.inputs,
		outputs = self.outputs,
		needs = needs,
	}
end

return Contract
