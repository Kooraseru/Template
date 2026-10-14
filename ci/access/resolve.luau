--!strict
local process = require("@lune/process")
local serde = require("@lune/serde")
local configuration = require("../lib/config")
local outputs = require("../lib/outputs")
local context = require("./context")
local policy = require("./policy")
local catalogue = require("../lib/catalogue")

local config = configuration.read()
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

-- act expands skipped matrices, and Lune encodes empty tables as objects.
local images = {}
for _, name in config.images.names do
    local image = catalogue.image(name)
    table.insert(images, { name = name, runner = image.runner, platform = image.platform })
end
if #images == 0 then
    table.insert(images, { name = "disabled", runner = config.build.runner, platform = "" })
end
values.image_matrix = serde.encode("json", { include = images })
values.build_matrix = serde.encode("json", { include = catalogue.targets(config) })
outputs.write(process.env.GITHUB_OUTPUT, values)
