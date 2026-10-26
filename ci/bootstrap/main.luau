-- ci/bootstrap/main.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")

local Contracts = require("./contracts")
local Planning = require("./planning")
local Glob = require("./glob")

local function fail(message: string): never
    error(message, 0)
end

local function argument(name: string): string
    for index, value in Process.args do
        if value == name then
            local nextValue = Process.args[index + 1]
            if not nextValue or nextValue:sub(1, 2) == "--" then
                fail(`missing argument for {name}`)
            end
            return nextValue
        end
    end
    fail(`missing required flag {name}`)
end

local function save(path: string, document)
    local directory = path:match("^(.*)/[^/]+$")
    if directory and not Fs.metadata(directory).exists then
        Fs.writeDir(directory)
    end
    Fs.writeFile(path, Serde.encode("json", document, true) .. "\n")
end

local function load(path: string)
    local ok, result = pcall(Serde.decode, "json", Fs.readFile(path))
    if not ok or type(result) ~= "table" then
        fail(`invalid CI artifact {path}: {result}`)
    end
    return result
end

local function same(left, right): boolean
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in left do
        if not same(value, right[key]) then
            return false
        end
    end
    for key in right do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function prepare(event: string)
    local validations, groups = Planning.Resolve(Contracts.Discover(), event)
    return {
        event = event,
        sha = Process.env.GITHUB_SHA or "",
        validations = validations,
        groups = Planning.Project(groups, event),
    }
end

local function outputsComplete(paths: { string }): { string }
    local missing = {}
    for _, path in paths do
        if path:find("*", 1, true) or path:find("?", 1, true) then
            if #Glob.Find(path) == 0 then
                table.insert(missing, path)
            end
        elseif not Fs.metadata(path).exists then
            table.insert(missing, path)
        end
    end
    return missing
end

local function invoke(task, event: string): boolean
    print(`::group::{task.identity}`)
    local ok, result = pcall(Process.exec, Process.env.CI_LUNE or "lune", {
        "run", "ci/bootstrap/invoke.luau", task.entry, event,
    }, { cwd = Process.cwd })
    if not ok then
        warn(`::error::{task.identity}: {result}`)
        print("::endgroup::")
        return false
    end
    if result.stdout ~= "" then
        print(result.stdout)
    end
    if result.stderr ~= "" then
        warn(result.stderr)
    end
    print("::endgroup::")
    if not result.ok then
        warn(`::error::{task.identity}: exited {result.code}`)
    end
    return result.ok
end

local function execute(tasks, event: string)
    local status = {}
    local results = {}
    local allPassed = true
    for _, task in tasks do
        local blockers = {}
        for _, needed in task.needs do
            if status[needed] ~= "passed" then
                table.insert(blockers, needed)
            end
        end
        local current: string
        if #blockers > 0 then
            current = "blocked"
            warn(`::error::{task.identity}: blocked by {table.concat(blockers, ", ")}`)
        else
            local passed = invoke(task, event)
            local missing = outputsComplete(task.outputs)
            if passed and #missing > 0 then
                warn(`::error::{task.identity}: missing declared outputs {table.concat(missing, ", ")}`)
            end
            current = if passed and #missing == 0 then "passed" else "failed"
        end
        status[task.identity] = current
        table.insert(results, { identity = task.identity, status = current })
        if current ~= "passed" then
            allPassed = false
        end
    end
    return results, allPassed
end

local function setOutput(key: string, value: string)
    if value:find("\n", 1, true) then
        fail(`invalid multiline GitHub output: {key}`)
    end
    local output = Process.env.GITHUB_OUTPUT
    if output then
        Fs.writeFile(output, Fs.readFile(output) .. `{key}={value}\n`)
    end
    print(`{key}: {value}`)
end

local function plan()
    local event = argument("--event")
    local destination = argument("--output")
    local document = prepare(event)
    local ordinary = Planning.Matrix(document.groups, "read")
    local privileged = Planning.Matrix(document.groups, "privileged")
    if #privileged.include > 0 then
        if event ~= "workflow_dispatch" or Process.env.GITHUB_REF ~= "refs/heads/source" then
            fail("privileged plans require manual dispatch on trusted source branch")
        end
    end
    local results, passed = execute(document.validations, event)
    if not passed then
        fail(`planning validation failed: {Serde.encode("json", results)}`)
    end
    save(destination, document)
    setOutput("matrix", Serde.encode("json", ordinary))
    setOutput("privileged_matrix", Serde.encode("json", privileged))
    setOutput("has_work", tostring(#ordinary.include > 0))
    setOutput("has_privileged", tostring(#privileged.include > 0))
    print(`Planned {#document.validations} validators and {#document.groups} execution groups`)
end

local function checkedPlan(path: string)
    local recorded = load(path)
    if type(recorded.event) ~= "string" then
        fail("plan artifact is missing event")
    end
    local expected = prepare(recorded.event)
    if not same(recorded, expected) then
        fail("plan differs from checked-out source or commit SHA")
    end
    return recorded
end

local function run()
    local source = argument("--plan")
    local id = argument("--group")
    local boundary = argument("--boundary")
    local destination = argument("--results")
    if boundary ~= "read" and boundary ~= "privileged" then
        fail(`invalid execution boundary: {boundary}`)
    end
    local document = checkedPlan(source)
    if boundary == "privileged" then
        if document.event ~= "workflow_dispatch" or Process.env.GITHUB_REF ~= "refs/heads/source" then
            fail("privileged execution requires trusted manual source dispatch")
        end
    end
    local group = nil
    for _, candidate in document.groups do
        if candidate.id == id then
            if group then
                fail(`duplicate planned group: {id}`)
            end
            group = candidate
        end
    end
    if not group or group.boundary ~= boundary then
        fail(`missing group or permission mismatch: {id}`)
    end
    local results, passed = execute(group.tasks, document.event)
    save(`{destination}/{id}.json`, {
        id = id,
        sha = document.sha,
        boundary = boundary,
        results = results,
    })
    if not passed then
        fail(`{id}: one or more tasks failed or were blocked`)
    end
end

local function reconcile()
    local source = argument("--plan")
    local directory = argument("--results")
    local document = checkedPlan(source)
    local expected = {}
    for _, group in document.groups do
        expected[group.id] = group
    end
    local observed = {}
    local failures = {}
    for _, path in Glob.Find(`{directory}/*.json`) do
        local receipt = load(path)
        local id = receipt.id
        local group = if type(id) == "string" then expected[id] else nil
        if not group or observed[id] then
            table.insert(failures, `unexpected or duplicate group receipt: {id}`)
            continue
        end
        observed[id] = true
        local actual = receipt.results
        if receipt.sha ~= document.sha or receipt.boundary ~= group.boundary or type(actual) ~= "table" or #actual ~= #group.tasks then
            table.insert(failures, `invalid receipt: {id}`)
            continue
        end
        for index, task in group.tasks do
            local result = actual[index]
            if type(result) ~= "table" or result.identity ~= task.identity or result.status ~= "passed" then
                table.insert(failures, `{id}: missing, failed or mismatched task {task.identity}`)
            end
        end
    end
    for id in expected do
        if not observed[id] then
            table.insert(failures, `missing group receipt: {id}`)
        end
    end
    if #failures > 0 then
        table.sort(failures)
        fail(`CI reconciliation failed:\n{table.concat(failures, "\n")}`)
    end
    print(`Reconciled {#document.groups} execution groups`)
end

local command = Process.args[1]
local ok, problem = pcall(function()
    if command == "plan" then
        plan()
    elseif command == "run" then
        run()
    elseif command == "reconcile" then
        reconcile()
    else
        fail("usage: lune run ci/bootstrap/main.luau plan|run|reconcile [flags]")
    end
end)
if not ok then
    warn(`::error::{problem}`)
    Process.exit(1)
end
