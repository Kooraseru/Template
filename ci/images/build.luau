--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local config = require("../lib/config").read()
assert(config.images.enabled, "image generation is disabled")
local name = process.args[1]
assert(table.find(config.images.names, name), "image is not configured")
local directory = "ci/images/" .. name
assert(fs.isFile(directory .. "/Dockerfile"), "missing image Dockerfile")
fs.writeDir("build/images/" .. name)
local tag = "template-ci/" .. name .. ":generated"
local built = process.exec("docker", { "build", "--tag", tag, directory }, { stdio = "inherit" })
assert(built.ok, "image build failed")
local saved =
    process.exec("docker", { "save", "--output", "build/images/" .. name .. "/image.tar", tag })
assert(saved.ok, "image export failed: " .. saved.stderr)
