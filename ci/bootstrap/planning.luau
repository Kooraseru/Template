-- ci/bootstrap/planning.luau
--!strict

local Planning = {}

-- Hosted runner classes are an adapter, not a hardcoded component inventory.
local HOSTED = {
    ["linux/x64"] = "ubuntu-latest",
    ["linux/arm64"] = "ubuntu-24.04-arm",
    ["windows/x64"] = "windows-latest",
    ["windows/arm64"] = "windows-11-arm",
    ["macos/arm64"] = "macos-15",
    ["macos/x64"] = "macos-15-intel",
}
local MATRIX_LIMIT = 256
local EVENTS = { push = true, pull_request = true, workflow_dispatch = true }

local function fail(message: string): never
    error(message, 0)
end

local function sortedKeys(map): { string }
    local keys = {}
    for key in map do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

local function contains(items: { string }, value: string): boolean
    return table.find(items, value) ~= nil
end

local function shape(component): string
    return `{component.runtime.os}/{component.runtime.architecture}/{table.concat(component.runtime.labels, ",")}/{component.boundary}`
end

local function orderedIds(active, dependencies): { string }
    local incoming = {}
    local outgoing = {}
    for identity in active do
        incoming[identity] = 0
        outgoing[identity] = {}
    end
    for identity, needs in dependencies do
        for needed in needs do
            incoming[identity] += 1
            table.insert(outgoing[needed], identity)
        end
    end
    local ready = {}
    for identity, count in incoming do
        if count == 0 then
            table.insert(ready, identity)
        end
    end
    table.sort(ready)
    local order = {}
    while #ready > 0 do
        local identity = table.remove(ready, 1)
        table.insert(order, identity)
        for _, successor in outgoing[identity] do
            incoming[successor] -= 1
            if incoming[successor] == 0 then
                table.insert(ready, successor)
            end
        end
        table.sort(ready)
    end
    if #order ~= #sortedKeys(active) then
        local remaining = {}
        for identity, count in incoming do
            if count > 0 then
                table.insert(remaining, identity)
            end
        end
        table.sort(remaining)
        fail(`dependency cycle: {table.concat(remaining, ", ")}`)
    end
    return order
end

function Planning.Resolve(components, event: string)
    if not EVENTS[event] then
        fail(`unsupported event: {event}`)
    end
    local active = {}
    for _, component in components do
        if component.enabled then
            active[component.identity] = component
        end
    end
    local providers = {}
    for _, identity in sortedKeys(active) do
        for _, capability in active[identity].provides do
            if providers[capability] then
                fail(`duplicate provider for {capability}: {providers[capability]} and {identity}`)
            end
            providers[capability] = identity
        end
    end
    local dependencies = {}
    local produced = {}
    for _, identity in sortedKeys(active) do
        local component = active[identity]
        for _, output in component.outputs do
            if produced[output] then
                fail(`output collision at {output}: {produced[output]} and {identity}`)
            end
            produced[output] = identity
        end
        local needs = {}
        for _, requirement in component.requires do
            local provider = providers[requirement]
            if not provider then
                fail(`{identity}: missing required capability {requirement}`)
            end
            needs[provider] = true
        end
        dependencies[identity] = needs
    end
    local order = orderedIds(active, dependencies)
    local selected = {}
    for _, identity in order do
        if contains(active[identity].events, event) then
            selected[identity] = true
        end
    end
    for identity in selected do
        for required in dependencies[identity] do
            if not selected[required] then
                fail(`{identity}: required provider {required} does not apply to {event}`)
            end
        end
    end
    local validators = {}
    local workers = {}
    for identity in selected do
        local validation = false
        for _, capability in active[identity].provides do
            if capability:sub(1, 11) == "validation." then
                validation = true
            end
        end
        if validation then
            validators[identity] = true
        else
            workers[identity] = true
        end
    end
    if next(workers) and not validators[providers["validation.preflight"]] then
        fail("nonempty CI requires a discovered, enabled, event-applicable validation.preflight provider")
    end
    for identity in validators do
        local component = active[identity]
        if shape(component) ~= "linux/x64//read" then
            fail(`{identity}: planning-time validators must use linux/x64, no labels, read boundary`)
        end
        for needed in dependencies[identity] do
            if not validators[needed] then
                fail(`{identity}: planning validator depends on non-validation task {needed}`)
            end
        end
    end

    local parent = {}
    for identity in workers do
        parent[identity] = identity
    end
    local function find(identity: string): string
        if parent[identity] ~= identity then
            parent[identity] = find(parent[identity])
        end
        return parent[identity]
    end
    for identity in workers do
        for needed in dependencies[identity] do
            if workers[needed] then
                if shape(active[identity]) ~= shape(active[needed]) then
                    fail(`unsupported cross-runner or boundary dependency: {needed} -> {identity}`)
                end
                parent[find(identity)] = find(needed)
            end
        end
    end

    local groupsByRoot = {}
    for _, identity in order do
        if not workers[identity] then
            continue
        end
        local root = find(identity)
        if not groupsByRoot[root] then
            local component = active[identity]
            groupsByRoot[root] = {
                runtime = component.runtime,
                boundary = component.boundary,
                tasks = {},
            }
        end
        local needs = {}
        for needed in dependencies[identity] do
            if workers[needed] then
                table.insert(needs, needed)
            end
        end
        table.sort(needs)
        table.insert(groupsByRoot[root].tasks, {
            identity = identity,
            entry = active[identity].entry,
            outputs = active[identity].outputs,
            needs = needs,
        })
    end
    local groups = {}
    for _, group in groupsByRoot do
        table.insert(groups, group)
    end
    table.sort(groups, function(a, b)
        return a.tasks[1].identity < b.tasks[1].identity
    end)

    local validations = {}
    for _, identity in order do
        if validators[identity] then
            local needs = {}
            for needed in dependencies[identity] do
                table.insert(needs, needed)
            end
            table.sort(needs)
            table.insert(validations, {
                identity = identity,
                entry = active[identity].entry,
                outputs = active[identity].outputs,
                needs = needs,
            })
        end
    end
    return validations, groups
end

function Planning.Project(groups, event: string)
    local projected = {}
    for _, group in groups do
        local runtime = group.runtime
        local runner = HOSTED[`{runtime.os}/{runtime.architecture}`]
        if #runtime.labels > 0 or not runner then
            fail(`no approved hosted runner for {runtime.os}/{runtime.architecture} with labels`)
        end
        if group.boundary == "privileged" and event ~= "workflow_dispatch" then
            fail("privileged work requires workflow_dispatch")
        end
        table.insert(projected, {
            runtime = runtime,
            boundary = group.boundary,
            runner = runner,
            tasks = group.tasks,
        })
    end
    if #projected > MATRIX_LIMIT then
        local shapes = {}
        for _, group in projected do
            local key = `{group.runner}/{group.boundary}`
            if not shapes[key] then
                shapes[key] = {}
            end
            table.insert(shapes[key], group)
        end
        local keys = sortedKeys(shapes)
        if #keys > MATRIX_LIMIT then
            fail(`too many incompatible runner shapes: {#keys}`)
        end
        local quota = {}
        for _, key in keys do
            quota[key] = 1
        end
        for _ = #keys + 1, MATRIX_LIMIT do
            local chosen = nil
            local remaining = 0
            for _, key in keys do
                local delta = #shapes[key] - quota[key]
                if delta > remaining then
                    chosen = key
                    remaining = delta
                end
            end
            if not chosen then
                break
            end
            quota[chosen] += 1
        end
        local combined = {}
        for _, key in keys do
            local buckets = {}
            for _ = 1, quota[key] do
                local group = shapes[key][1]
                table.insert(buckets, {
                    runtime = group.runtime,
                    boundary = group.boundary,
                    runner = group.runner,
                    tasks = {},
                })
            end
            for index, group in shapes[key] do
                local bucket = buckets[(index - 1) % #buckets + 1]
                for _, task in group.tasks do
                    table.insert(bucket.tasks, task)
                end
            end
            for _, bucket in buckets do
                table.insert(combined, bucket)
            end
        end
        projected = combined
    end
    table.sort(projected, function(a, b)
        return a.tasks[1].identity < b.tasks[1].identity
    end)
    for index, group in projected do
        group.id = string.format("group-%03d", index - 1)
    end
    return projected
end

function Planning.Matrix(groups, boundary: string)
    local include = {}
    for _, group in groups do
        if group.boundary == boundary then
            table.insert(include, { group = group.id, runner = group.runner })
        end
    end
    return { include = include }
end

return Planning
