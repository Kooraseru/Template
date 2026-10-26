-- ci/bootstrap/component.luau
--!strict

-- Each discovered CI component owns a validated contract instance. Parsing
-- untrusted TOML never imports or executes the component implementation.

local Component = {}
Component.__index = Component

--# Types

type Runtime = {
	os: string,
	architecture: string,
	labels: { string },
}

type ComponentFields = {
	identity: string,
	entry: string,
	provides: { string },
	requires: { string },
	inputs: { string },
	outputs: { string },
	events: { string },
	runtime: Runtime,
	boundary: string,
	enabled: boolean,
}

export type Component = setmetatable<ComponentFields, typeof(Component)>

export type Task = {
	identity: string,
	entry: string,
	outputs: { string },
	needs: { string },
}

--# Constants

local EVENTS = { push = true, pull_request = true, workflow_dispatch = true }
local OPERATING_SYSTEMS = { linux = true, windows = true, macos = true }
local ARCHITECTURES = { x64 = true, arm64 = true }
local VALIDATION_PREFIX = "validation."

--# Helpers

local function invalid(entry: string, reason: string): never
	error(`{entry}: {reason}`, 0)
end

local function strings(entry: string, field: string, value: unknown, pattern: string?): { string }
	if type(value) ~= "table" then
		invalid(entry, `{field} must be an array`)
	end

	local items = {}
	local seen = {}
	local candidates = value :: { [any]: unknown }
	for index, item in candidates do
		if type(index) ~= "number" or index ~= #items + 1 or type(item) ~= "string" or item == "" then
			invalid(entry, `{field} must contain only nonempty strings`)
		end
		if seen[item] then
			invalid(entry, `duplicate {field}: {item}`)
		end
		if pattern and not item:match(pattern) then
			invalid(entry, `invalid {field}: {item}`)
		end
		seen[item] = true
		table.insert(items, item)
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

local function executionRuntime(entry: string, value: unknown): Runtime
	if type(value) ~= "table" then
		invalid(entry, "runtime must declare os and architecture")
	end
	local raw = value :: { [string]: unknown }
	if type(raw.os) ~= "string" or not OPERATING_SYSTEMS[raw.os] then
		invalid(entry, "unsupported runtime.os")
	end
	if type(raw.architecture) ~= "string" or not ARCHITECTURES[raw.architecture] then
		invalid(entry, "unsupported runtime.architecture")
	end

	local fields: Runtime = {
		os = raw.os,
		architecture = raw.architecture,
		labels = strings(entry, "runtime.labels", raw.labels or {}, "^[a-z][a-z0-9_.:-]*$"),
	}
	for field in raw do
		if rawget(fields, field) == nil then
			invalid(entry, `unknown runtime field: {field}`)
		end
	end
	return fields
end

--# Constructor

-- The constructed fields are the runtime shape owner. The same fields define
-- which TOML keys are valid; no second ALLOWED_FIELDS table or return-table copy.
function Component.new(identity: string, entry: string, source: unknown): Component
	if type(source) ~= "table" then
		invalid(entry, "ci-contract must decode to a TOML table")
	end
	local raw = source :: { [string]: unknown }
	if identity == "init" or not identity:match("^[%a%d][%w_-]*$") then
		invalid(entry, `invalid component identity: {identity}`)
	end

	local provides = strings(entry, "provides", raw.provides, "^[a-z][a-z0-9_.:-]*$")
	if #provides == 0 then
		invalid(entry, "provides must not be empty")
	end

	local events = strings(entry, "events", raw.events or { "push", "pull_request", "workflow_dispatch" })
	if #events == 0 then
		invalid(entry, "events must not be empty")
	end
	for _, event in events do
		if not EVENTS[event] then
			invalid(entry, `unsupported event: {event}`)
		end
	end

	local boundary = raw.boundary or "read"
	if boundary ~= "read" and boundary ~= "privileged" then
		invalid(entry, "boundary must be read or privileged")
	end

	local enabled = raw.enabled
	if enabled == nil then
		enabled = true
	elseif type(enabled) ~= "boolean" then
		invalid(entry, "enabled must be boolean")
	end

	local fields: ComponentFields = {
		identity = identity,
		entry = entry,
		provides = provides,
		requires = strings(entry, "requires", raw.requires or {}, "^[a-z][a-z0-9_.:-]*$"),
		inputs = paths(entry, "inputs", raw.inputs or {}),
		outputs = paths(entry, "outputs", raw.outputs or {}),
		events = events,
		runtime = executionRuntime(entry, raw.runtime),
		boundary = boundary,
		enabled = enabled,
	}
	for field in raw do
		-- Identity and entry come from discovery, not from the contract source.
		if rawget(fields, field) == nil then
			invalid(entry, `unknown or reserved contract field: {field}`)
		end
	end

	return setmetatable(fields, Component)
end

--# Methods

function Component.SupportsEvent(self: Component, event: string): boolean
	return table.find(self.events, event) ~= nil
end

function Component.IsValidator(self: Component): boolean
	for _, capability in self.provides do
		if capability:sub(1, #VALIDATION_PREFIX) == VALIDATION_PREFIX then
			return true
		end
	end
	return false
end

function Component.RunnerShape(self: Component): string
	local runtime = self.runtime
	return `{runtime.os}/{runtime.architecture}/{table.concat(runtime.labels, ",")}/{self.boundary}`
end

-- Convert a validated instance to the minimum serializable execution record.
-- Method tables and other local state never cross the artifact boundary.
function Component.ToTask(self: Component, needs: { string }): Task
	return {
		identity = self.identity,
		entry = self.entry,
		outputs = self.outputs,
		needs = needs,
	}
end

return Component
