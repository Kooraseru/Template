--!strict
local process = require("@lune/process")
local serde = require("@lune/serde")
local configuration = require("../lib/config")
local outputs = require("../lib/outputs")
local context = require("./context")
local policy = require("./policy")

local config = configuration.read()
local resolved = process.exec("lune", { "run", "ci/releases/resolve.luau" })
assert(resolved.ok, "could not resolve build inputs: " .. resolved.stdout .. resolved.stderr)
local fs = require("@lune/fs")
local matrices = serde.decode("json", fs.readFile("build/tmp/releases/outputs.json"))
local canPublish = policy.canPublish(context.read(process.env))
local values = {
    publish = tostring(canPublish),
    runner = config.build.runner,
    rust = tostring(table.find(config.build.toolchains, "rust") ~= nil),
    cmake = tostring(table.find(config.build.toolchains, "cmake") ~= nil),
    rust_version = config.build.rust_version,
    cmake_version = config.build.cmake_version,
}

local capabilities: { [string]: configuration.Capability } = {
    repository = config.repository,
    pages = config.pages,
    release = config.release,
    images = config.images,
}
for name, capability in capabilities do
    values[name] = tostring(capability.enabled)
    values["publish_" .. name] = tostring(canPublish and capability.publish)
end

values.images = matrices.images_enabled
values.image_matrix = matrices.image_matrix
values.build_matrix = matrices.build_matrix
values.release_matrix = matrices.release_matrix
outputs.write(process.env.GITHUB_OUTPUT, values)
