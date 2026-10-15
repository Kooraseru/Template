-- ci/releases/resolve.luau
--!strict
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Process = require("@lune/process")
local Inputs = require("../lib/inputs")
local Configuration = require("../lib/config")
local Catalogue = require("../lib/catalogue")
local Rules = require("../lib/rules")
local config = Configuration.Read()
local headResult = Process.exec("git", { "rev-parse", "HEAD" })
assert(headResult.ok, "cannot resolve controller commit")
local head = headResult.stdout:gsub("%s+$", "")
local tested = Process.env.CI_TESTED_SHA or head
Fs.writeDir("build/tmp/releases")
local releasing = config.release.enabled and (Process.env.CI_RECEIPT_PR or "0") == "0"
local versions = if releasing then Serde.decode("toml", Fs.readFile("ci/releases/versions.toml")) else { releases = {} }
local controls = require("../control/config").Read()
Fs.writeFile("build/tmp/releases/request.json", Serde.encode("json", {
    versions = versions, enabled = releasing, controls = controls,
}))
local resolve = Process.exec("node", { "ci/releases/cli.mjs", "resolve" })
assert(resolve.ok, "release version resolution failed (" .. tostring(resolve.code) .. "): " .. resolve.stdout .. resolve.stderr)
local selections = Serde.decode("json", Fs.readFile("build/tmp/releases/selections.json")) :: { { source_sha: string } }
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
    Inputs.ref = snapshot.sha
    local selected = Configuration.Read()
    Catalogue.Validate(Catalogue.Read(selected))
    for _, target in Catalogue.Targets(selected) do
        local entry = table.clone(Rules.Entries(target))
        local imageName = target.image or ""
        entry.source_sha = snapshot.sha
        entry.input_ref = Inputs.ref
        entry.current = snapshot.current
        entry.artifact = "distribution-" .. snapshot.sha .. "-" .. target.name
        entry.image_artifact = if imageName == "" then "" else "image-" .. snapshot.sha .. "-" .. imageName
        entry.build = selected.build
        local imageDefinition = if imageName == "" then nil else Catalogue.Image(imageName)
        entry.image_definition = imageDefinition
        local recipes: { [string]: string } = {}
        if imageDefinition then
            for _, file in { imageDefinition.recipe, "toolchains/" .. (target.profile or "") .. "/Dockerfile", "install.sh" } do
                recipes[file] = Inputs.Read("ci/images/" .. file)
            end
        end
        entry.recipes = recipes
        table.insert(builds, entry)
    end
    if selected.images.enabled then
        for _, name in selected.images.names do
            local image = Catalogue.Image(name)
            local recipes = {}
            for _, file in { image.recipe, "toolchains/" .. image.profile .. "/Dockerfile", "install.sh" } do
                recipes[file] = Inputs.Read("ci/images/" .. file)
            end
            table.insert(images, { name = name, runner = image.runner, source_sha = snapshot.sha,
                input_ref = Inputs.ref, definition = image, recipes = recipes })
        end
    end
end
Inputs.ref = ""
Fs.writeFile("build/tmp/releases/inputs.json", Serde.encode("json", {
    controller_sha = head, builds = builds, images = images, selections = selections,
}))
local finalize = Process.exec("node", { "ci/releases/cli.mjs", "plan" })
assert(finalize.ok, "release build planning failed: " .. finalize.stdout .. finalize.stderr)
