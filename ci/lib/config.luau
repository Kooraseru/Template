--!strict
local serde = require("@lune/serde")
local config = {}
local inputs = require("./inputs")

local rules = require("./rules")
local schema = rules.read("ci/validation/ruleset.json", "config.rules")

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
    repository: Capability & { include: { string } },
    pages: Capability & { title: string },
    release: Capability,
    images: Capability & { names: { string } },
    build: {
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

function config.relative(value: any): string
    rules.check(value, schema.definitions.relative, "relative path")
    return value
end

-- Runtime constraints are defined in the data schema, not duplicated here.
function config.validate(value: any): Config
    local resolved = if type(value) == "table" then table.clone(value) else value
    for _, definition in schema.rules do
        if definition.default ~= nil then
            local parts = string.split(definition.path, ".")
            local section, name = parts[1], parts[2]
            if type(resolved) == "table" and type(resolved[section]) == "table" then
                local settings = table.clone(resolved[section])
                if settings[name] == nil then
                    local fallback = definition.default
                    settings[name] = if type(fallback) == "table"
                        then table.clone(fallback)
                        else fallback
                end
                resolved[section] = settings
            end
        end
    end
    rules.validate(resolved, schema)
    return resolved
end

function config.read(): Config
    local value = serde.decode("toml", inputs.read("ci/config.toml"))
    -- Older snapshots may contain the retired registry-publication flag.
    if inputs.ref ~= "" then value.images.publish = false end
    return config.validate(require("../control/config").apply(value))
end

return config
