-- ci/lib/rules.luau
--!strict

local Rules = {}
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")

export type Condition = { path: string, equals: unknown, contains: unknown }
export type Rule = {
    path: string?, kind: string?, message: string?, equals: unknown,
    equals_path: string?, enum: { unknown }?, not_values: { unknown }?,
    min_length: number?, exact_length: number?, min_items: number?,
    pattern: string?, prefix: string?, contains: unknown,
    required_substrings: { string }?, capture_pattern: string?, capture_length: number?,
    reject_patterns: { string }?, reject_substrings: { string }?,
    forbidden_components: { string }?, unique: boolean?, unique_by: string?,
    exists: boolean?, absent: boolean?, optional: boolean?, skip_pattern: string?,
    when: Condition?, use: string?, default: unknown,
    key_count: number?, count_where: { field: string, equals: unknown, count: number }?,
    requires_before: { field: string, value: string, prerequisite: string }?,
}
export type RepositoryCheck = { operation: string, path: string?, expected: { string }?, paths: { string }?, config_path: string?, text: string? }
export type Document = {
    rules: { Rule }, definitions: { [string]: Rule }, collections: { Document },
    definitions_source: string?, definitions_section: string?, actions: Document?,
    path: string?, key_pattern: string?, exclude_keys: { string }?, exclude_key_pattern: string?,
    checks: { RepositoryCheck }?,
    relations: { { source: string, destination: string, field: string?, skip: unknown,
        enabled_path: string?, key: string?, equal_fields: { string }? } }?,
    paths: { { source: string, template: string } }?,
    manifest_file: string?, hash_algorithm: "sha256"?, hash_field: string?,
    controls: { source: string, path: string, default_type: string }?,
}

export type Dictionary = { [string | number]: unknown }

-- JSON/YAML tables have string or numeric keys. Keep values uncertain until checked.
local function entries(value: unknown): Dictionary
    assert(type(value) == "table", "expected a data table")
    for key in value do
        assert(type(key) == "string" or type(key) == "number", "invalid data key")
    end
    return value :: Dictionary
end
Rules.Entries = entries

-- Copies a dense sequence, retaining unknown element values for later validation.
local function array(value: unknown): { unknown }
    local source = entries(value)
    local result = {}
    local count = 0
    for key in source do
        count += 1
        assert(type(key) == "number" and key >= 1 and key % 1 == 0 and key <= #source, "expected a dense array")
    end
    assert(count == #source, "expected a dense array")
    for index = 1, #source do table.insert(result, source[index]) end
    return result
end
Rules.Array = array

local vocabulary = entries(Serde.decode("json", Fs.readFile("ci/validation/ruleset.json")))
local format = entries(entries(entries(vocabulary.rules).format).fields)

local function inspectRule(raw: unknown): Rule
    local value = entries(raw)
    for key, child in value do
        local expected = assert(format[key], "unknown validation option: " .. tostring(key))
        assert(expected == "any" or type(child) == expected, "invalid validation option: " .. tostring(key))
    end
    if value.count_where then
        local filter = entries(value.count_where)
        assert(type(filter.field) == "string" and type(filter.count) == "number", "invalid entry count filter")
    end
    if value.requires_before then
        local order = entries(value.requires_before)
        assert(type(order.field) == "string" and type(order.value) == "string"
            and type(order.prerequisite) == "string", "invalid ordered prerequisite")
    end
    -- Rule fields are quarantined until the vocabulary check above succeeds.
    return value :: Rule
end

-- Resolves an optional dot-path section and rejects unknown rule options before use.
function Rules.Read(path: string, section: string?): Document
    local raw: unknown = Serde.decode("json", Fs.readFile(path))
    if section then
        for _, key in string.split(section, ".") do
            raw = assert(entries(raw)[key], "missing validation section: " .. section)
        end
    end
    assert(type(raw) == "table", "expected validation document")
    -- Quarantine decoded JSON at this boundary. Inspect its rule vocabulary before use.
    local document = raw :: Document
    local function inspectDocument(value: Document)
        value.rules = value.rules or {}
        value.definitions = value.definitions or {}
        value.collections = value.collections or {}
        for _, rule in value.rules or {} do
            inspectRule(rule)
        end
        for _, rule in value.definitions or {} do
            inspectRule(rule)
        end
        for _, collection in value.collections or {} do
            inspectDocument(collection)
        end
        if value.actions then
            inspectDocument(value.actions)
        end
    end
    inspectDocument(document)
    document.rules = document.rules or {}
    document.definitions = document.definitions or {}
    document.collections = document.collections or {}
    if document.definitions_source then
        document.definitions = Rules.Read(document.definitions_source, document.definitions_section).definitions
    end
    return document
end

local function property(value: unknown, path: string): unknown
    if path == "$" then
        return value
    end
    for _, part in string.split(path, ".") do
        if type(value) ~= "table" then
            return nil
        end
        value = entries(value)[tonumber(part) or part]
    end
    return value
end
Rules.Property = property

local function enabled(root: unknown, condition: Condition?): boolean
    if not condition then
        return true
    end
    local value = property(root, condition.path)
    if condition.contains ~= nil then
        return type(value) == "table" and table.find(array(value), condition.contains) ~= nil
    end
    return value == condition.equals
end

function Rules.Check(value: unknown, rule: Rule, location: string)
    local message = rule.message or ("invalid value at " .. location)
    if rule.exists then
        assert(value ~= nil, message .. ": missing value")
    end
    if rule.absent then
        assert(value == nil, message .. ": unexpected value")
    end
    if rule.kind == "array" then
        assert(type(value) == "table", message .. ": expected an array")
        for key in value do
            assert(
                type(key) == "number" and key >= 1 and key % 1 == 0 and key <= #value,
                message .. ": expected a dense array"
            )
        end
    elseif rule.kind == "object" then
        assert(type(value) == "table", message .. ": expected an object")
        for key in value do
            assert(type(key) == "string", message .. ": expected object keys")
        end
    elseif rule.kind then
        assert(type(value) == rule.kind, message .. ": expected " .. rule.kind)
    end
    if rule.equals ~= nil then
        assert(value == rule.equals, message)
    end
    if rule.enum then
        assert(table.find(rule.enum, value), message .. ": unsupported value")
    end
    if rule.not_values then
        assert(not table.find(rule.not_values, value), message .. ": reserved value")
    end
    if rule.min_length then
        assert(type(value) == "string", message)
        assert(#value >= rule.min_length, message .. ": string is too short")
    end
    if rule.exact_length then
        assert(type(value) == "string", message)
        assert(#value == rule.exact_length, message .. ": wrong length")
    end
    if rule.min_items then
        assert(type(value) == "table", message)
        assert(#value >= rule.min_items, message .. ": too few items")
    end
    if rule.pattern then
        assert(type(value) == "string", message)
        assert(value:match(rule.pattern), message .. ": pattern mismatch")
    end
    if rule.prefix then
        assert(type(value) == "string", message)
        assert(value:sub(1, #rule.prefix) == rule.prefix, message .. ": wrong prefix")
    end
    if rule.contains ~= nil then
        assert(type(value) == "table", message)
        assert(table.find(array(value), rule.contains), message .. ": missing item")
    end
    for _, text in rule.required_substrings or {} do
        assert(type(value) == "string", message)
        assert(value:find(text, 1, true), message .. ": missing substring")
    end
    if rule.capture_pattern then
        assert(type(value) == "string", message)
        local captured = value:match(rule.capture_pattern)
        assert(captured and #captured == rule.capture_length, message .. ": invalid capture")
    end
    for _, pattern in rule.reject_patterns or {} do
        assert(type(value) == "string", message)
        assert(not value:find(pattern), message .. ": forbidden pattern")
    end
    for _, text in rule.reject_substrings or {} do
        assert(type(value) == "string", message)
        assert(not value:find(text, 1, true), message .. ": forbidden substring")
    end
    if rule.forbidden_components then
        assert(type(value) == "string", message)
        for component in value:gmatch("[^/]+") do
            assert(
                not table.find(rule.forbidden_components, component),
                message .. ": forbidden component"
            )
        end
    end
    if rule.unique or rule.unique_by then
        assert(type(value) == "table", message)
        local seen = {}
        for _, item in value do
            local key = if rule.unique_by then property(item, rule.unique_by) else item
            assert(key ~= nil and not seen[key], message .. ": missing or duplicate item")
            seen[key] = true
        end
    end
    if rule.key_count or rule.count_where then
        assert(type(value) == "table", message)
        local count = 0
        for _, child in value do
            if not rule.count_where or property(child, rule.count_where.field) == rule.count_where.equals then
                count += 1
            end
        end
        local expected = if rule.count_where then rule.count_where.count else rule.key_count
        assert(count == expected, message .. ": wrong entry count")
    end
    if rule.requires_before then
        assert(type(value) == "table", message)
        local ready = false
        for _, child in value do
            local selected = property(child, rule.requires_before.field)
            if selected == rule.requires_before.value then
                assert(ready, message .. ": missing earlier prerequisite")
            end
            if selected == rule.requires_before.prerequisite then ready = true end
        end
    end

end

-- Missing fields remain uncertain until the selected constraints accept them.
-- The input is inspected in place and is never normalized or copied here.
function Rules.Validate(root: unknown, document: Document)
    for _, definition in document.rules do
        if enabled(root, definition.when) then
            local merged = if definition.use
                then table.clone(entries(assert(document.definitions[definition.use], "unknown rule definition")))
                else {}
            for key, value in entries(definition) do
                -- Additive constraints preserve restrictions inherited from a definition.
                if key == "reject_patterns" and merged[key] then
                    local patterns = array(merged[key])
                    for _, pattern in entries(value) do
                        table.insert(patterns, pattern)
                    end
                    merged[key] = patterns
                else
                    merged[key] = value
                end
            end
            local rule = inspectRule(merged)
            local rulePath = assert(rule.path, "missing rule path")
            local parts = if rulePath == "$" then {} else string.split(rulePath, ".")
            local function visit(value: unknown, index: number, location: string)
                if rule.optional and value == nil then
                    return
                end
                if index > #parts then
                    local skip = false
                    if rule.skip_pattern then
                        assert(type(value) == "string", "expected pattern input at " .. location)
                        skip = value:match(rule.skip_pattern) ~= nil
                    end
                    if not skip then
                        if rule.equals_path then
                            assert(
                                value == property(root, rule.equals_path),
                                "mismatched fields at " .. location
                            )
                        end
                        Rules.Check(value, rule, location)
                    end
                elseif parts[index] == "*" then
                    assert(type(value) == "table", "expected a collection at " .. location)
                    for key, child in value do
                        visit(child, index + 1, location .. "." .. tostring(key))
                    end
                else
                    local key = tonumber(parts[index]) or parts[index]
                    local child = if type(value) == "table" then entries(value)[key] else nil
                    visit(child, index + 1, location .. "." .. tostring(parts[index]))
                end
            end
            visit(root, 1, "$")
        end
    end
    for _, collection in document.collections or {} do
        local collectionPath = assert(collection.path, "missing collection path")
        local values = property(root, collectionPath)
        assert(type(values) == "table", "expected collection at " .. collectionPath)
        for key, value in values do
            local name = tostring(key)
            if
                (not collection.key_pattern or name:match(collection.key_pattern))
                and (not collection.exclude_keys or not table.find(collection.exclude_keys, name))
                and (
                    not collection.exclude_key_pattern
                    or not name:match(collection.exclude_key_pattern)
                )
            then
                Rules.Validate(value, collection)
            end
        end
    end
end

return Rules
