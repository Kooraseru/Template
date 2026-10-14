--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local configuration = require("./config")
local rules = require("./rules")
local catalogue = {}
local imageDefinitions = serde.decode("json", fs.readFile("ci/images/catalogue.json"))
local targetDefinitions = serde.decode("json", fs.readFile("ci/build/targets.json"))
local schema = rules.read("ci/validation/catalogue.rules.json")

function catalogue.read(config: configuration.Config): any
    return { images = imageDefinitions.images, targets = targetDefinitions.targets, config = config }
end

function catalogue.validate(document: any)
    rules.validate(document, schema)
    local selected = if #document.config.build.matrix > 0 then document.config.build.matrix else {}
    if #document.config.build.matrix == 0 then
        for _, name in document.config.build.targets do
            for _, target in document.targets do
                if target.name == name then
                    table.insert(selected, target)
                end
            end
        end
    end
    document.selected = selected
    for _, relation in schema.relations do
        local destination = rules.property(document, relation.destination)
        for _, entry in rules.property(document, relation.source) do
            local value = if relation.field then rules.property(entry, relation.field) else entry
            if value ~= nil and value ~= relation.skip then
                if relation.enabled_path then
                    assert(
                        rules.property(document, relation.enabled_path),
                        "reference requires enabled capability"
                    )
                end
                local matched: any = nil
                for _, candidate in destination do
                    local key = if relation.key
                        then rules.property(candidate, relation.key)
                        else candidate
                    if key == value then
                        matched = candidate
                        break
                    end
                end
                assert(matched ~= nil, "unknown reference: " .. tostring(value))
                for _, field in relation.equal_fields or {} do
                    assert(entry[field] == matched[field], "mismatched reference field: " .. field)
                end
            end
        end
    end
    for _, definition in schema.paths do
        for _, entry in rules.property(document, definition.source) do
            local path = definition.template:gsub("{([^}]+)}", function(field)
                return tostring(rules.property(entry, field))
            end)
            assert(fs.isFile(path), "missing catalogue input: " .. path)
        end
    end
end

function catalogue.image(name: string): any
    for _, entry in imageDefinitions.images do
        if entry.name == name then
            return entry
        end
    end
    error("Unknown CI image: " .. name)
end

function catalogue.targets(config: configuration.Config): { configuration.BuildEntry }
    local entries = {}
    if #config.build.matrix > 0 then
        entries = config.build.matrix
    elseif #config.build.targets > 0 then
        for _, name in config.build.targets do
            local found = false
            for _, target in targetDefinitions.targets do
                if target.name == name then
                    table.insert(entries, target)
                    found = true
                    break
                end
            end
            assert(found, "Unknown build target: " .. name)
        end
    else
        entries = { { name = "default", runner = config.build.runner } }
    end
    local result = {}
    for _, entry in entries do
        local target = table.clone(entry)
        target.image = target.image or ""
        target.platform = target.platform or ""
        target.profile = target.profile or ""
        target.target = target.target or ""
        target.environment = target.environment or {}
        target.probes = target.probes or {}
        target.rust_version = target.rust_version or ""
        target.msvc_arch = target.msvc_arch or ""
        table.insert(result, target)
    end
    return result
end

function catalogue.target(config: configuration.Config, name: string): configuration.BuildEntry
    for _, entry in catalogue.targets(config) do
        if entry.name == name then
            return entry
        end
    end
    error("Unknown selected build target: " .. name)
end

return catalogue
