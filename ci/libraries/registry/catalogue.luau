-- libraries/registry/catalogue.luau
--!strict

local Catalogue = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Configuration = require("./config")
local Rules = require("./rules")
local Inputs = require("../bootstrap/inputs")
--# Types

export type Image = {
	name: string,
	runner: string,
	platform: string,
	profile: string,
	base: string,
	version: string,
	recipe: string,
	common_packages: { string },
	packages: { string },
	inventory: { string },
	probes: { Configuration.Probe },
}

export type Document = {
	images: { Image },
	targets: { Configuration.BuildEntry },
	config: Configuration.Config,
	selected: { Configuration.BuildEntry }?,
}
--# Helpers

local function images(): { images: { Image } }
	local document: unknown = Serde.decode("json", Inputs.Read("fabricator/distribution/images/catalogue.json"))

	assert(type(document) == "table", "expected image catalogue")

	return document :: { images: { Image } }
end

local function targets(): { targets: { Configuration.BuildEntry } }
	local document: unknown = Serde.decode("json", Inputs.Read("fabricator/targets.json"))

	assert(type(document) == "table", "expected target catalogue")

	return document :: { targets: { Configuration.BuildEntry } }
end

local schema = Rules.Read("validation/ruleset.json", "catalogue.rules")

--# Functions

function Catalogue.Read(config: Configuration.Config): Document

	return { images = images().images, targets = targets().targets, config = config }
end

function Catalogue.Validate(raw: unknown)
	Rules.Validate(raw, schema)
	local document = raw :: Document
	local selected = if #document.config.build.matrix > 0 then document.config.build.matrix else {}

	if #document.config.build.matrix == 0 then
		for _, name in document.config.build.targets do
			for _, target in document.targets do
				if target.name == name then
					table.insert(selected, target)
				end
			end
		end
	end
	document.selected = selected

	for _, relation in assert(schema.relations, "missing catalogue relations") do
		local destination = Rules.Property(document, relation.destination)

		for _, entry in Rules.Entries(Rules.Property(document, relation.source)) do
			local value = if relation.field then Rules.Property(entry, relation.field) else entry

			if value ~= nil and value ~= relation.skip then
				if relation.enabled_path then
					assert(Rules.Property(document, relation.enabled_path), "reference requires enabled capability")
				end

				local matched: unknown = nil

				for _, candidate in Rules.Entries(destination) do
					local key = if relation.key then Rules.Property(candidate, relation.key) else candidate

					if key == value then
						matched = candidate
						break
					end
				end

				assert(matched ~= nil, "unknown reference: " .. tostring(value))

				for _, field in relation.equal_fields or {} do
					assert(
						Rules.Entries(entry)[field] == Rules.Entries(matched)[field],
						"mismatched reference field: " .. field
					)
				end
			end
		end
	end

	for _, definition in assert(schema.paths, "missing catalogue paths") do
		for _, entry in Rules.Entries(Rules.Property(document, definition.source)) do
			local path = definition.template:gsub("{([^}]+)}", function(field)
				return tostring(Rules.Property(entry, field))
			end)

			assert(Fs.isFile(path), "missing catalogue input: " .. path)
		end
	end
end

function Catalogue.Image(name: string): Image

	for _, entry in images().images do
		if entry.name == name then
			return entry
		end
	end
	error("Unknown CI image: " .. name)
end

function Catalogue.Targets(config: Configuration.Config): { Configuration.BuildEntry }
	local entries = {}

	if #config.build.matrix > 0 then
		entries = config.build.matrix
	elseif #config.build.targets > 0 then
		for _, name in config.build.targets do
			local found = false

			for _, target in targets().targets do
				if target.name == name then
					table.insert(entries, target)
					found = true
					break
				end
			end

			assert(found, "Unknown build target: " .. name)
		end
	else
		entries = { { name = "default", runner = config.build.runner } }
	end

	local result = {}

	for _, entry in entries do
		local target = table.clone(entry)
		target.image = target.image or ""
		target.platform = target.platform or ""
		target.profile = target.profile or ""
		target.target = target.target or ""
		target.environment = target.environment or {}
		target.probes = target.probes or {}
		target.rust_version = target.rust_version or ""
		target.msvc_arch = target.msvc_arch or ""
		table.insert(result, target)
	end

	return result
end

function Catalogue.Target(config: Configuration.Config, name: string): Configuration.BuildEntry

	for _, entry in Catalogue.Targets(config) do
		if entry.name == name then
			return entry
		end
	end
	error("Unknown selected build target: " .. name)
end

return Catalogue
