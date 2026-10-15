--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local controls = require("../config")
local config = require("../../lib/config")
local catalogue = require("../../lib/catalogue")
local baseline = serde.decode("toml", fs.readFile("ci/config.toml"))
local originalRead = controls.read
local function resolve(selected: any): any
    controls.read = function() return selected end
    return config.validate(controls.apply(baseline))
end

local selected = resolve({ build_targets = "All supported" })
assert(#catalogue.targets(selected) == 32, "All supported must select the complete catalogue")
assert(selected.images.enabled, "Selecting container targets must enable their images")
selected = resolve({ build_targets = "Windows", compiler = "MSVC", architecture = "ARM64" })
assert(#catalogue.targets(selected) == 1 and catalogue.targets(selected)[1].name == "windows-msvc-arm64")
selected = resolve({ build_targets = "macOS", architecture = "x64" })
assert(#catalogue.targets(selected) == 2)
selected = resolve({ build_targets = "alpine-gcc-x64", images = "Required by selected builds" })
assert(#selected.images.names == 1 and selected.images.names[1] == "alpine-gcc-x64")
catalogue.validate(catalogue.read(selected))
selected = resolve({ build_targets = "alpine-gcc-x64" })
assert(#selected.images.names == 1, "A selected target must not activate unrelated dormant images")
assert(not pcall(resolve, { build_targets = "Windows", compiler = "GCC" }), "Empty target intersections must fail")
selected = resolve({ build_targets = "alpine-gcc-x64", images = "Skip" })
assert(not pcall(catalogue.validate, catalogue.read(selected)), "Skipping required images must fail")
selected = resolve({ images = "All catalogue images" })
assert(#selected.images.names > 1 and selected.images.enabled)
selected = resolve({ repository_output = "Skip", documentation_output = "Generate only", release_output = "Publish beta" })
assert(not selected.repository.enabled and not selected.repository.publish)
assert(selected.pages.enabled and not selected.pages.publish)
assert(selected.release.enabled and selected.release.publish)
assert(baseline.repository.enabled and baseline.repository.publish, "Overrides must not mutate the baseline")
controls.read = originalRead
print("CI control configuration cases passed")
