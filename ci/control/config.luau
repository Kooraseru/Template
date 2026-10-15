-- ci/control/config.luau
--!strict

local Control = {}
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Inputs = require("../lib/inputs")
local Rules = require("../lib/rules")

type Target = { name: string, runner: string, platform: string?, target: string?, profile: string?, image: string? }
type BuildOverrides = { matrix: { Target }, targets: { string } }
type ImageOverrides = { names: { string }, enabled: boolean }

function Control.Read(): { [string]: string }
    if Process.env.GITHUB_EVENT_NAME ~= "workflow_dispatch" then return {} end
    local raw: unknown = {}
    if Process.env.CI_CONTROL_INPUTS then
        raw = Serde.decode("json", Process.env.CI_CONTROL_INPUTS)
    elseif Process.env.GITHUB_EVENT_PATH then
        local event = Rules.Entries(Serde.decode("json", require("@lune/fs").readFile(Process.env.GITHUB_EVENT_PATH)))
        raw = event.inputs or {}
    end
    local selected = {}
    for key, value in Rules.Entries(raw) do
        assert(type(key) == "string" and type(value) == "string", "expected string workflow inputs")
        selected[key] = value
    end
    return selected
end

-- Apply run overrides in memory to both current and historical source configurations.
function Control.Apply(raw: unknown): unknown
    local value = Rules.Entries(raw)
    local selected = Control.Read()
    if next(selected) == nil then return value end
    local result = table.clone(value)
    for _, name in { "build", "images", "repository", "pages", "release" } do
        result[name] = table.clone(Rules.Entries(value[name]))
    end
    local build = Rules.Entries(result.build) :: BuildOverrides
    local imageOutput = Rules.Entries(result.images) :: ImageOverrides
    local targetChoice = selected.build_targets or "Configured"
    local compiler = selected.compiler or "Any"
    local architecture = selected.architecture or "Any"
    local targetDocument = Rules.Entries(Serde.decode("json", Inputs.Read("ci/build/targets.json")))
    local targets = Rules.Array(targetDocument.targets) :: { Target }
    local imageDocument = Rules.Entries(Serde.decode("json", Inputs.Read("ci/images/catalogue.json")))
    local images = Rules.Array(imageDocument.images) :: { { name: string } }
    local selecting = targetChoice ~= "Configured" or compiler ~= "Any" or architecture ~= "Any"
    if selecting then
        local entries = {}
        if targetChoice == "Configured" then
            if #(build.matrix or {}) > 0 then
                entries = build.matrix
            else
                for _, name in build.targets or {} do
                    for _, target in targets do
                        if target.name == name then table.insert(entries, target) end
                    end
                end
            end
        else
            for _, target in targets do
                local os = if target.runner:match("^windows") then "Windows"
                    elseif target.runner:match("^macos") then "macOS" else "Linux"
                if targetChoice == "All supported" or targetChoice == os or targetChoice == target.name then
                    table.insert(entries, target)
                end
            end
        end
        local names = {}
        build.matrix = {}
        for _, target in entries do
            local identity = target.name .. " " .. (target.platform or "") .. " " .. (target.target or "")
            local arch = if identity:find("arm64") or identity:find("aarch64") then "ARM64" else "x64"
            if (compiler == "Any" or string.lower(compiler) == target.profile)
                and (architecture == "Any" or architecture == arch) then
                -- Catalogue entries retain their original probe and provenance contracts.
                table.insert(build.matrix, target)
                table.insert(names, target.name)
            end
        end
        assert(#names > 0, "Build target, compiler and architecture selections have no matching targets")
        build.targets = {}
    end
    local imageChoice = selected.images or "Configured"
    if imageChoice == "Skip" then
        imageOutput.enabled = false
        imageOutput.names = {}
    elseif imageChoice == "All catalogue images" then
        imageOutput.enabled = true
        imageOutput.names = {}
        for _, image in images do table.insert(imageOutput.names, image.name) end
    elseif imageChoice == "Required by selected builds" or (imageChoice == "Configured" and selecting) then
        imageOutput.names = table.clone(imageOutput.names or {})
        if imageChoice == "Required by selected builds" or not imageOutput.enabled then imageOutput.names = {} end
        local entries = build.matrix or {}
        if #entries == 0 then
            for _, name in build.targets or {} do
                for _, target in targets do
                    if target.name == name then table.insert(entries, target) end
                end
            end
        end
        for _, target in entries do
            if target.image and target.image ~= "" and not table.find(imageOutput.names, target.image) then
                table.insert(imageOutput.names, target.image)
            end
        end
        imageOutput.enabled = #imageOutput.names > 0
    end
    local outputSections: { [string]: string } = { repository_output = "repository", documentation_output = "pages", release_output = "release" }
    for key, name in outputSections do
        local choice = selected[key] or "Configured"
        if choice ~= "Configured" then
            Rules.Entries(result[name]).enabled = choice ~= "Skip"
            Rules.Entries(result[name]).publish = choice == "Generate and publish" or choice:match("^Publish") ~= nil
        end
    end
    return result
end

return Control
