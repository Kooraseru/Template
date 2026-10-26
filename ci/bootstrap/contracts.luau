-- ci/bootstrap/contracts.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Glob = require("./glob")

local Contracts = {}

local ALLOWED_FIELDS = {
    provides = true,
    requires = true,
    inputs = true,
    outputs = true,
    events = true,
    runtime = true,
    boundary = true,
    enabled = true,
}
local ALLOWED_EVENTS = { pull_request = true, push = true, workflow_dispatch = true }
local ALLOWED_OS = { linux = true, windows = true, macos = true }
local ALLOWED_ARCH = { x64 = true, arm64 = true }

local function fail(entry: string, message: string): never
    error(`{entry}: {message}`, 0)
end

local function stringList(entry: string, key: string, value: unknown, pattern: string?): { string }
    if type(value) ~= "table" then
        fail(entry, `{key} must be an array`)
    end
    local result = {}
    local seen = {}
    for index, item in (value :: { unknown }) do
        if type(index) ~= "number" or index ~= #result + 1 or type(item) ~= "string" or item == "" then
            fail(entry, `{key} must contain only nonempty strings`)
        end
        if pattern and not item:match(pattern) then
            fail(entry, `invalid {key} value: {item}`)
        end
        if seen[item] then
            fail(entry, `duplicate {key} value: {item}`)
        end
        seen[item] = true
        table.insert(result, item)
    end
    return result
end

local function paths(entry: string, key: string, value: unknown): { string }
    local result = stringList(entry, key, value)
    for _, path in result do
        if path:sub(1, 1) == "/" or path:find("\\", 1, true) or path:find(":", 1, true) then
            fail(entry, `unsafe {key} glob: {path}`)
        end
        for part in path:gmatch("[^/]+") do
            if part == "." or part == ".." then
                fail(entry, `unsafe {key} glob: {path}`)
            end
        end
        if path:find("//", 1, true) or path:sub(-1) == "/" then
            fail(entry, `invalid {key} glob: {path}`)
        end
    end
    return result
end

local function read(entry: string, identity: string)
    local source = Fs.readFile(entry):gsub("\r\n", "\n")
    local header = `-- {entry}\n--!strict\n--[[ci-contract\n`
    if source:sub(1, #header) ~= header then
        fail(entry, "missing leading path label, --!strict, or ci-contract TOML comment")
    end
    local marker = "\nend-ci-contract]]"
    local finish = source:find(marker, #header + 1, true)
    if not finish then
        fail(entry, "unterminated ci-contract comment")
    end
    local success, decoded = pcall(Serde.decode, "toml", source:sub(#header + 1, finish - 1))
    if not success or type(decoded) ~= "table" then
        fail(entry, `invalid contract TOML: {decoded}`)
    end
    local raw = decoded :: { [string]: unknown }
    for field in raw do
        if not ALLOWED_FIELDS[field] then
            fail(entry, `unknown contract field {field}`)
        end
    end
    local provides = stringList(entry, "provides", raw.provides, "^[a-z][a-z0-9_.:-]*$")
    if #provides == 0 then
        fail(entry, "provides must not be empty")
    end
    local requires = stringList(entry, "requires", raw.requires or {}, "^[a-z][a-z0-9_.:-]*$")
    local inputs = paths(entry, "inputs", raw.inputs or {})
    local outputs = paths(entry, "outputs", raw.outputs or {})
    local events = stringList(entry, "events", raw.events or { "push", "pull_request", "workflow_dispatch" })
    if #events == 0 then
        fail(entry, "events must not be empty")
    end
    for _, event in events do
        if not ALLOWED_EVENTS[event] then
            fail(entry, `unsupported event {event}`)
        end
    end
    if type(raw.runtime) ~= "table" then
        fail(entry, "runtime must be a table with os and architecture")
    end
    local runtime = raw.runtime :: { [string]: unknown }
    for field in runtime do
        if field ~= "os" and field ~= "architecture" and field ~= "labels" then
            fail(entry, `unknown runtime field {field}`)
        end
    end
    if type(runtime.os) ~= "string" or not ALLOWED_OS[runtime.os] then
        fail(entry, "unsupported runtime.os")
    end
    if type(runtime.architecture) ~= "string" or not ALLOWED_ARCH[runtime.architecture] then
        fail(entry, "unsupported runtime.architecture")
    end
    local labels = stringList(entry, "runtime.labels", runtime.labels or {}, "^[a-z][a-z0-9_.:-]*$")
    local boundary = raw.boundary or "read"
    if boundary ~= "read" and boundary ~= "privileged" then
        fail(entry, "boundary must be read or privileged")
    end
    local enabled = raw.enabled
    if enabled == nil then
        enabled = true
    elseif type(enabled) ~= "boolean" then
        fail(entry, "enabled must be boolean")
    end
    return {
        identity = identity,
        entry = entry,
        provides = provides,
        requires = requires,
        inputs = inputs,
        outputs = outputs,
        events = events,
        runtime = { os = runtime.os, architecture = runtime.architecture, labels = labels },
        boundary = boundary,
        enabled = enabled,
    }
end

function Contracts.Discover()
    if not Fs.isDir("ci/components") then
        error("missing ci/components extension point", 0)
    end
    local components = {}
    local identities = {}
    for _, path in Glob.Find("ci/components/*") do
        local name = path:match("([^/]+)$")
        if name == ".gitkeep" then
            continue
        end
        local metadata = Fs.metadata(path)
        local identity: string
        local entry: string
        if metadata.kind == "file" and name:sub(-5) == ".luau" then
            identity = name:sub(1, -6)
            entry = path
        elseif metadata.kind == "dir" then
            identity = name
            entry = `{path}/init.luau`
            if not Fs.isFile(entry) or Fs.metadata(entry).kind == "symlink" then
                fail(path, "component directory requires init.luau")
            end
        else
            fail(path, "invalid direct child of ci/components")
        end
        if identity == "init" or not identity:match("^[%a%d][%w_-]*$") then
            fail(path, `invalid component identity {identity}`)
        end
        local folded = identity:lower()
        if identities[folded] then
            fail(path, `ambiguous component identity {identity}; conflicts with {identities[folded]}`)
        end
        identities[folded] = path
        table.insert(components, read(entry, identity))
    end
    return components
end

return Contracts
