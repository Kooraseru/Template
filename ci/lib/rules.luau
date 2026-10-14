--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local rules = {}
local format = serde.decode("json", fs.readFile("ci/validation/rule-format.json"))

function rules.read(path: string): any
    local document = serde.decode("json", fs.readFile(path))
    local function inspect(rule: any)
        for key, value in rule do
            local expected =
                assert(format.fields[key], "unknown validation option: " .. tostring(key))
            assert(
                expected == "any" or type(value) == expected,
                "invalid validation option: " .. key
            )
        end
    end
    local function inspectDocument(value: any)
        for _, rule in value.rules or {} do
            inspect(rule)
        end
        for _, rule in value.definitions or {} do
            inspect(rule)
        end
        for _, collection in value.collections or {} do
            inspectDocument(collection)
        end
        if value.actions then
            inspectDocument(value.actions)
        end
    end
    inspectDocument(document)
    if document.definitions_source then
        document.definitions = rules.read(document.definitions_source).definitions
    end
    return document
end

local function property(value: any, path: string): any
    if path == "$" then
        return value
    end
    for _, part in string.split(path, ".") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[tonumber(part) or part]
    end
    return value
end
rules.property = property

local function enabled(root: any, condition: any): boolean
    if not condition then
        return true
    end
    local value = property(root, condition.path)
    if condition.contains ~= nil then
        return type(value) == "table" and table.find(value, condition.contains) ~= nil
    end
    return value == condition.equals
end

function rules.check(value: any, rule: any, location: string)
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
        assert(#value >= rule.min_length, message .. ": string is too short")
    end
    if rule.exact_length then
        assert(#value == rule.exact_length, message .. ": wrong length")
    end
    if rule.min_items then
        assert(#value >= rule.min_items, message .. ": too few items")
    end
    if rule.pattern then
        assert(value:match(rule.pattern), message .. ": pattern mismatch")
    end
    if rule.prefix then
        assert(value:sub(1, #rule.prefix) == rule.prefix, message .. ": wrong prefix")
    end
    if rule.contains ~= nil then
        assert(table.find(value, rule.contains), message .. ": missing item")
    end
    for _, text in rule.required_substrings or {} do
        assert(value:find(text, 1, true), message .. ": missing substring")
    end
    if rule.capture_pattern then
        local captured = value:match(rule.capture_pattern)
        assert(captured and #captured == rule.capture_length, message .. ": invalid capture")
    end
    for _, pattern in rule.reject_patterns or {} do
        assert(not value:find(pattern), message .. ": forbidden pattern")
    end
    for _, text in rule.reject_substrings or {} do
        assert(not value:find(text, 1, true), message .. ": forbidden substring")
    end
    if rule.forbidden_components then
        for component in value:gmatch("[^/]+") do
            assert(
                not table.find(rule.forbidden_components, component),
                message .. ": forbidden component"
            )
        end
    end
    if rule.unique or rule.unique_by then
        local seen = {}
        for _, item in value do
            local key = if rule.unique_by then property(item, rule.unique_by) else item
            assert(key ~= nil and not seen[key], message .. ": missing or duplicate item")
            seen[key] = true
        end
    end
end

function rules.validate(root: any, document: any)
    for _, definition in document.rules do
        if enabled(root, definition.when) then
            local rule: { [string]: any } = if definition.use
                then table.clone(document.definitions[definition.use])
                else {}
            for key, value in definition do
                -- Additive constraints preserve restrictions inherited from a definition.
                if key == "reject_patterns" and rule[key] then
                    local patterns = table.clone(rule[key])
                    for _, pattern in value do
                        table.insert(patterns, pattern)
                    end
                    rule[key] = patterns
                else
                    rule[key] = value
                end
            end
            local parts = if rule.path == "$" then {} else string.split(rule.path, ".")
            local function visit(value: any, index: number, location: string)
                if rule.optional and value == nil then
                    return
                end
                if index > #parts then
                    if not rule.skip_pattern or not value:match(rule.skip_pattern) then
                        if rule.equals_path then
                            assert(
                                value == property(root, rule.equals_path),
                                "mismatched fields at " .. location
                            )
                        end
                        rules.check(value, rule, location)
                    end
                elseif parts[index] == "*" then
                    assert(type(value) == "table", "expected a collection at " .. location)
                    for key, child in value do
                        visit(child, index + 1, location .. "." .. tostring(key))
                    end
                else
                    local key = tonumber(parts[index]) or parts[index]
                    local child = if type(value) == "table" then value[key] else nil
                    visit(child, index + 1, location .. "." .. parts[index])
                end
            end
            visit(root, 1, "$")
        end
    end
    for _, collection in document.collections or {} do
        local values = property(root, collection.path)
        assert(type(values) == "table", "expected collection at " .. collection.path)
        for key, value in values do
            local name = tostring(key)
            if
                (not collection.key_pattern or name:match(collection.key_pattern))
                and (
                    not collection.exclude_key_pattern
                    or not name:match(collection.exclude_key_pattern)
                )
            then
                rules.validate(value, collection)
            end
        end
    end
end

return rules
