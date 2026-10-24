-- ci/fabricator/config.luau
--!strict

local Config = {}

--# Modules

local Project = require("./project")
local Targets = require("./targets")
local Shape = require("../utilities/shape")

local Rules = require("../validation/rules")
local schema = Rules.Read("ci/validation/ruleset.json", "config.rules")

--# Types

export type Capability = { enabled: boolean, publish: boolean }

export type Probe = { argv: { string }, code: number, stdout_contains: string? }

export type BuildEntry = {
	name: string,
	runner: string,
	image: string?,
	platform: string?,
	profile: string?,
	target: string?,
	environment: { [string]: string }?,
	probes: { Probe }?,
	rust_version: string?,
	msvc_arch: string?,
	reuse_identity: string?,
	reproducible: boolean?,
}

export type Config = {
	targets: { Targets.Target },
	repository: Capability & { include: { string } },
	pages: Capability & { title: string },
	release: Capability,
	images: Capability & { names: { string } },
	build: {
		projects: { string }?,
		runner: string,
		matrix: { BuildEntry },
		targets: { string },
		toolchains: { string },
		rust_version: string,
		cmake_version: string,
		commands: { { string } },
		package_paths: { string },
	},
}

export type BuildSpec = BuildEntry & {
	project_targets: { Targets.Target }?,
	build: index<Config, "build">,
	source_sha: string,
	fingerprint: string,
	image_artifact: string,
}

--# Functions

function Config.Relative(value: unknown): string
	Rules.Check(value, schema.definitions.relative, "relative path")
	assert(type(value) == "string", "expected relative path")

	return value
end

-- Runtime constraints are defined in the data schema, not duplicated here.
function Config.Validate(value: unknown): Config
	assert(type(value) == "table", "expected CI configuration")
	local resolved = table.clone(Rules.Entries(value))

	for _, definition in schema.rules do
		if definition.default ~= nil then
			local parts = string.split(assert(definition.path, "missing default path"), ".")
			local section, name = parts[1], parts[2]

			if type(resolved) == "table" and type(resolved[section]) == "table" then
				local settings = table.clone(Rules.Entries(resolved[section]))

				if settings[name] == nil then
					local fallback = definition.default
					settings[name] = if type(fallback) == "table" then table.clone(fallback) else fallback
				end
				resolved[section] = settings
			end
		end
	end
	Rules.Validate(resolved, schema)
	local build = Rules.Entries(resolved.build)
	local projects = if build.projects ~= nil then Shape.Strings(build.projects, "project selection") else nil
	resolved.targets = Targets.Select(Targets.Validate(resolved.targets or {}), projects)

	return resolved :: Config
end

function Config.Read(): Config
	local value = Project.Read()

	return Config.Validate(require("../integration/config").Apply(value))
end

return Config
