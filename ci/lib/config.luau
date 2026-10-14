--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local config = {}

local rules = require("./rules")
local schema = rules.read("ci/validation/config.rules.json")

export type Capability = { enabled: boolean, publish: boolean }
export type BuildEntry = { name: string, runner: string }
export type Config = {
    repository: Capability & { include: { string } },
    pages: Capability & { title: string },
    release: Capability & { version: string },
    images: Capability & { names: { string } },
    build: {
        runner: string,
        matrix: { BuildEntry },
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
    rules.validate(value, schema)
    return value
end

function config.read(): Config
    return config.validate(serde.decode("toml", fs.readFile("ci/config.toml")))
end

return config
