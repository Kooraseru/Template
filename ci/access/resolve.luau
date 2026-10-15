-- ci/access/resolve.luau
--!strict
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Configuration = require("../lib/config")
local Outputs = require("../lib/outputs")
local Context = require("./context")
local Policy = require("./policy")

local config = Configuration.Read()
local resolved = Process.exec("lune", { "run", "ci/releases/resolve.luau" })
assert(resolved.ok, "could not resolve build inputs: " .. resolved.stdout .. resolved.stderr)
local receipts = Process.exec("node", { "ci/receipts/cli.mjs", "plan" })
assert(receipts.ok, "could not resolve accepted validation: " .. receipts.stdout .. receipts.stderr)
local Fs = require("@lune/fs")
local matrices = Serde.decode("json", Fs.readFile("build/tmp/releases/outputs.json")) :: { [string]: string }
local canPublish = Policy.CanPublish(Context.Read(Process.env))
local values = {
    publish = tostring(canPublish),
    runner = config.build.runner,
    rust = tostring(table.find(config.build.toolchains, "rust") ~= nil),
    cmake = tostring(table.find(config.build.toolchains, "cmake") ~= nil),
    rust_version = config.build.rust_version,
    cmake_version = config.build.cmake_version,
}

local capabilities: { [string]: Configuration.Capability } = {
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
values.release = matrices.release_enabled
values.publish_release = tostring(canPublish and config.release.publish and matrices.release_enabled == "true")
values.build_requested = matrices.build_requested
values.receipt_ready = matrices.receipt_ready
values.accepted_available = matrices.accepted_available
values.local_execution = matrices.local_execution
Outputs.Write(Process.env.GITHUB_OUTPUT, values)
