--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local inputs = require("../lib/inputs")
local configuration = require("../lib/config")
local catalogue = require("../lib/catalogue")
local config = configuration.read()
local headResult = process.exec("git", { "rev-parse", "HEAD" })
assert(headResult.ok, "cannot resolve controller commit")
local head = headResult.stdout:gsub("%s+$", "")
local tested = process.env.CI_TESTED_SHA or head
fs.writeDir("build/tmp/releases")
local releasing = config.release.enabled and (process.env.CI_RECEIPT_PR or "0") == "0"
local versions = if releasing then serde.decode("toml", fs.readFile("ci/releases/versions.toml")) else { releases = {} }
local controls = require("../control/config").read()
fs.writeFile("build/tmp/releases/request.json", serde.encode("json", {
    versions = versions, enabled = releasing, controls = controls,
}))
local resolve = process.exec("node", { "ci/releases/cli.mjs", "resolve" })
assert(resolve.ok, "release version resolution failed (" .. tostring(resolve.code) .. "): " .. resolve.stdout .. resolve.stderr)
local selections = serde.decode("json", fs.readFile("build/tmp/releases/selections.json"))
local snapshots = { { sha = tested, current = true } }
local seen = { [tested] = true }
for _, selection in selections do
    if not seen[selection.source_sha] then
        table.insert(snapshots, { sha = selection.source_sha, current = false })
        seen[selection.source_sha] = true
    end
end
local builds, images = {}, {}
for _, snapshot in snapshots do
    inputs.ref = snapshot.sha
    local selected = configuration.read()
    catalogue.validate(catalogue.read(selected))
    for _, target in catalogue.targets(selected) do
        local entry: any = table.clone(target)
        entry.source_sha = snapshot.sha
        entry.input_ref = inputs.ref
        entry.current = snapshot.current
        entry.artifact = "distribution-" .. snapshot.sha .. "-" .. target.name
        entry.image_artifact = if entry.image == "" then "" else "image-" .. snapshot.sha .. "-" .. entry.image
        entry.build = selected.build
        entry.image_definition = if entry.image == "" then nil else catalogue.image(entry.image)
        entry.recipes = {}
        if entry.image_definition then
            for _, file in { entry.image_definition.recipe, "toolchains/" .. entry.profile .. "/Dockerfile", "install.sh" } do
                entry.recipes[file] = inputs.read("ci/images/" .. file)
            end
        end
        table.insert(builds, entry)
    end
    if selected.images.enabled then
        for _, name in selected.images.names do
            local image = catalogue.image(name)
            local recipes = {}
            for _, file in { image.recipe, "toolchains/" .. image.profile .. "/Dockerfile", "install.sh" } do
                recipes[file] = inputs.read("ci/images/" .. file)
            end
            table.insert(images, { name = name, runner = image.runner, source_sha = snapshot.sha,
                input_ref = inputs.ref, definition = image, recipes = recipes })
        end
    end
end
inputs.ref = ""
fs.writeFile("build/tmp/releases/inputs.json", serde.encode("json", {
    controller_sha = head, builds = builds, images = images, selections = selections,
}))
local finalize = process.exec("node", { "ci/releases/cli.mjs", "plan" })
assert(finalize.ok, "release build planning failed: " .. finalize.stdout .. finalize.stderr)
