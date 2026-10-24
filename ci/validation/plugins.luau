-- ci/validation/plugins.luau
--!strict

local Plugins = {}

--# Modules

local Shape = require("../utilities/shape")

--# Types

export type Contract = {
	Capabilities: { string },
	Permissions: { string },
	Modes: { string },
}

export type Descriptor = {
	id: string,
	provides: { string },
	requires: { string },
	permissions: { string },
	entry: { mode: string, name: string?, path: string? },
}

export type Source = { Descriptor: unknown, Bundled: boolean }

export type Host = {
	Contract: Contract,
	Bundled: boolean,
	Granted: { string },
	Interfaces: { [string]: { string } },
}

--# Helpers

local function recognized(values: { string }, supported: { string }, label: string)
	for _, value in values do
		assert(table.find(supported, value), "unsupported " .. label .. ": " .. value)
	end
end

--# Functions

function Plugins.Validate(value: unknown, contract: Contract, bundled: boolean): Descriptor
	local fields = Shape.Object(value, { "id", "provides", "requires", "permissions", "entry" })
	local entry = Shape.Object(fields.entry, { "mode", "name", "path" })
	local mode = Shape.Text(entry.mode, "execution mode")
	assert(table.find(contract.Modes, mode), "unsupported execution mode: " .. mode)
	assert(mode == "builtin" or mode == "worker" or mode == "trusted", "unrecognized execution mode: " .. mode)
	local descriptor: Descriptor = {
		id = Shape.Text(fields.id, "plugin identifier"),
		provides = Shape.Strings(fields.provides, "provided capability"),
		requires = Shape.Strings(fields.requires, "required capability"),
		permissions = Shape.Strings(fields.permissions, "requested permission"),
		entry = { mode = mode },
	}

	if mode == "builtin" then
		assert(bundled, "user plugin cannot claim built-in authority")
		assert(entry.path == nil, "built-in entry cannot declare an executable path")
		descriptor.entry.name = Shape.Text(entry.name, "built-in registration name")
	else
		assert(entry.name == nil, "external entry cannot declare a built-in registration")
		descriptor.entry.path = Shape.Relative(entry.path)
	end

	recognized(descriptor.provides, contract.Capabilities, "provided capability")
	recognized(descriptor.requires, contract.Capabilities, "required capability")
	recognized(descriptor.permissions, contract.Permissions, "permission")

	return descriptor
end

function Plugins.Resolve(providers: { Descriptor }, capability: string, selected: string?): Descriptor
	local found: Descriptor? = nil

	for _, provider in providers do
		if table.find(provider.provides, capability) and (selected == nil or selected == provider.id) then
			assert(not found, "ambiguous provider: " .. capability)
			found = provider
		end
	end

	assert(found, "missing provider: " .. capability)

	return found
end

function Plugins.ValidateActivation(value: unknown, host: Host, registrations: unknown): Descriptor

	local descriptor = Plugins.Validate(value, host.Contract, host.Bundled)
	local providers = Shape.Object(registrations, descriptor.provides)

	for _, permission in descriptor.permissions do
		assert(table.find(host.Granted, permission), "permission not authorized by host: " .. permission)
	end

	for _, capability in descriptor.provides do
		local methods = assert(host.Interfaces[capability], "missing host API shape: " .. capability)
		assert(#methods > 0, "empty host API shape: " .. capability)
		local implementation = Shape.Object(providers[capability], methods)

		for _, method in methods do
			assert(type(implementation[method]) == "function", "missing API method: " .. capability .. "." .. method)
		end
	end

	return descriptor
end

function Plugins.ValidateAll(sources: { Source }, contract: Contract, selections: { [string]: string }?): { Descriptor }
	local descriptors: { Descriptor } = {}
	local ids: { [string]: boolean } = {}

	for _, source in sources do
		local descriptor = Plugins.Validate(source.Descriptor, contract, source.Bundled)
		assert(not ids[descriptor.id], "duplicate plugin identifier: " .. descriptor.id)
		ids[descriptor.id] = true
		table.insert(descriptors, descriptor)
	end

	local active: { [string]: boolean } = {}
	local complete: { [string]: boolean } = {}
	local choices = selections or {}

	local function visit(descriptor: Descriptor)
		assert(not active[descriptor.id], "circular plugin requirements: " .. descriptor.id)

		if complete[descriptor.id] then
			return
		end

		active[descriptor.id] = true

		for _, capability in descriptor.requires do
			visit(Plugins.Resolve(descriptors, capability, choices[capability]))
		end

		active[descriptor.id] = nil
		complete[descriptor.id] = true
	end

	-- Check conflicts even when no other descriptor requires the capability.
	for _, descriptor in descriptors do
		for _, capability in descriptor.provides do
			Plugins.Resolve(descriptors, capability, choices[capability])
		end

		visit(descriptor)
	end

	return descriptors
end

return Plugins
