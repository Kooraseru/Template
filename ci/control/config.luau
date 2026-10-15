--!strict
local process = require("@lune/process")
local serde = require("@lune/serde")
local inputs = require("../lib/inputs")
local control = {}

function control.read(): any
    if process.env.GITHUB_EVENT_NAME ~= "workflow_dispatch" then return {} end
    if process.env.CI_CONTROL_INPUTS then return serde.decode("json", process.env.CI_CONTROL_INPUTS) end
    if process.env.GITHUB_EVENT_PATH then
        return serde.decode("json", require("@lune/fs").readFile(process.env.GITHUB_EVENT_PATH)).inputs or {}
    end
    return {}
end

-- Apply run overrides in memory to both current and historical source configurations.
function control.apply(value: any): any
    local selected = control.read()
    if next(selected) == nil then return value end
    local result = table.clone(value)
    for _, name in { "build", "images", "repository", "pages", "release" } do
        result[name] = table.clone(value[name])
    end
    local targetChoice = selected.build_targets or "Configured"
    local compiler = selected.compiler or "Any"
    local architecture = selected.architecture or "Any"
    local targets = serde.decode("json", inputs.read("ci/build/targets.json")).targets
    local images = serde.decode("json", inputs.read("ci/images/catalogue.json")).images
    local selecting = targetChoice ~= "Configured" or compiler ~= "Any" or architecture ~= "Any"
    if selecting then
        local entries = {}
        if targetChoice == "Configured" then
            if #(result.build.matrix or {}) > 0 then
                entries = result.build.matrix
            else
                for _, name in result.build.targets or {} do
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
        result.build.matrix = {}
        for _, target in entries do
            local identity = target.name .. " " .. (target.platform or "") .. " " .. (target.target or "")
            local arch = if identity:find("arm64") or identity:find("aarch64") then "ARM64" else "x64"
            if (compiler == "Any" or string.lower(compiler) == target.profile)
                and (architecture == "Any" or architecture == arch) then
                -- Catalogue entries retain their original probe and provenance contracts.
                table.insert(result.build.matrix, target)
                table.insert(names, target.name)
            end
        end
        assert(#names > 0, "Build target, compiler and architecture selections have no matching targets")
        result.build.targets = {}
    end
    local imageChoice = selected.images or "Configured"
    if imageChoice == "Skip" then
        result.images.enabled = false
        result.images.names = {}
    elseif imageChoice == "All catalogue images" then
        result.images.enabled = true
        result.images.names = {}
        for _, image in images do table.insert(result.images.names, image.name) end
    elseif imageChoice == "Required by selected builds" or (imageChoice == "Configured" and selecting) then
        result.images.names = table.clone(result.images.names or {})
        if imageChoice == "Required by selected builds" or not result.images.enabled then result.images.names = {} end
        local entries = result.build.matrix or {}
        if #entries == 0 then
            for _, name in result.build.targets or {} do
                for _, target in targets do
                    if target.name == name then table.insert(entries, target) end
                end
            end
        end
        for _, target in entries do
            if target.image and target.image ~= "" and not table.find(result.images.names, target.image) then
                table.insert(result.images.names, target.image)
            end
        end
        result.images.enabled = #result.images.names > 0
    end
    for key, name in { repository_output = "repository", documentation_output = "pages", release_output = "release" } do
        local choice = selected[key] or "Configured"
        if choice ~= "Configured" then
            result[name].enabled = choice ~= "Skip"
            result[name].publish = choice == "Generate and publish" or choice:match("^Publish") ~= nil
        end
    end
    return result
end

return control
