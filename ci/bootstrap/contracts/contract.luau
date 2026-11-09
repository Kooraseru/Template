-- ci/bootstrap/contracts/contract.luau
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
	credentials: { string },
	enabled: boolean,
}

export type Contract = setmetatable<ContractFields, typeof(Contract)>

export type Task = {
	boundary: string,
	credentials: { string },
	identity: string,
	invoker: string,
	entry: string,
	contractFile: string,
	inputs: { string },
	outputs: { string },
	needs: { string },
}

--# Constants

const TASK_INVOKER = "ci/bootstrap/execution/invoke.luau"
const COMPONENT_ROOT = "ci/components"
Contract.ComponentRoot = COMPONENT_ROOT

--# Helpers

--- Attribute a validation failure to its manifest instead of the helper that raised it.
local function invalid(entry: string, reason: string): never
	error(`{entry}: {reason}`, 0)
end

--- Validate a dense array of unique nonempty strings and preserve its declared order.
local function strings(entry: string, field: string, value: unknown, pattern: string?): { string }
	if type(value) ~= "table" then
		return invalid(entry, `{field} must be an array`)
	end

	local items: { string } = {}
	local seen: { [string]: boolean } = {}
	local count = 0
	local maxIndex = 0

	-- Check every key because Luau array length alone cannot reliably identify sparse input.
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

	-- Positive integral keys form a dense array only when the count reaches the maximum index.
	if count ~= maxIndex then
		return invalid(entry, `{field} must be a contiguous array`)
	end
	return items
end

--- Reject globs that could escape the workspace or resolve differently across platforms.
local function paths(entry: string, field: string, value: unknown): { string }
	local items = strings(entry, field, value)
	-- Check separators and traversal segments before the planner expands the globs.
	for _, path in items do
		if
			path:sub(1, 1) == "/"
			or path:find("\\", 1, true)
			or path:find(":", 1, true)
			or path:find("//", 1, true)
			or path:sub(-1) == "/"
		then
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

--# Functions

--- Restrict scheduling to the events understood by the bootstrap entry point.
function Contract.ValidEvent(event: string): boolean
	return event == "push" or event == "pull_request" or event == "workflow_dispatch"
end

--- Keep component IDs safe as relative paths and reserve init for the module entry.
function Contract.ValidIdentity(identity: string): boolean
	if identity == "" or identity:sub(1, 1) == "/" or identity:sub(-1) == "/" or identity:find("//", 1, true) then
		return false
	end
	for segment in identity:gmatch("[^/]+") do
		if segment == "init" or not segment:match("^[%a%d][%w_-]*$") then
			return false
		end
	end
	return true
end

--- Escape separators and the escape character without merging distinct identities.
function Contract.Key(identity: string): string
	local key = identity:gsub("_", "_u"):gsub("/", "_s")
	return key
end

--# Constructor

--[[
	Validates decoded component metadata before planning. Invalid declarations report the contract file so the owner can correct it.

	@param source unknown The decoded TOML value at the trust boundary.
]]
function Contract.new(identity: string, entry: string, contractFile: string, source: unknown): Contract
	if type(source) ~= "table" then
		return invalid(contractFile, "component manifest must contain a table")
	end
	local raw: { [string]: unknown } = {}

	-- Narrow decoded TOML to string keys before looking up named manifest fields.
	for field, value in source do
		if type(field) ~= "string" then
			return invalid(contractFile, "manifest keys must be strings")
		end
		raw[field] = value
	end

	-- Validate the path-derived identity before exposing it to the planner.
	if not Contract.ValidIdentity(identity) then
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
		if not Contract.ValidEvent(event) then
			invalid(contractFile, `unsupported event: {event}`)
		end
	end

	-- Treat omitted boundaries as read access so privileged execution requires an explicit declaration.
	local boundary = raw.boundary
	local boundaryValue: string
	-- Accept only the boundary values understood by the scheduler.
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

	-- Normalize optional lists so the planner can iterate them without handling missing values.
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
		credentials = strings(contractFile, "credentials", raw.credentials or {}, "^[a-z][a-z0-9_]*$"),
		enabled = true,
	}
	if boundaryValue ~= "privileged" and #fields.credentials > 0 then
		invalid(contractFile, "credentials require a privileged boundary")
	end
	-- Reject unknown fields so a misspelled policy cannot silently take effect as a default.
	for field in raw do
		if field ~= "provides" and field ~= "requires" and field ~= "inputs" and field ~= "outputs"
			and field ~= "events" and field ~= "boundary" and field ~= "credentials" then
			invalid(contractFile, `unknown or reserved contract field: {field}`)
		end
	end

	return setmetatable(fields, Contract)
end

--# Methods

--- Tell the planner whether this manifest participates in the requested event.
function Contract.SupportsEvent(self: Contract, event: string): boolean
	return table.find(self.events, event) ~= nil
end

--[[
Convert a validated instance to the minimum serializable execution record.
Method tables and other local state never cross the artifact boundary.
]]
function Contract.ToTask(self: Contract, needs: { string }): Task
	return {
		boundary = self.boundary,
		credentials = self.credentials,
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
