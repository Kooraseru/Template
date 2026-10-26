-- ci/bootstrap/glob.luau
--!strict

local Fs = require("@lune/fs")

local Glob = {}

local function split(path: string): { string }
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    return parts
end

local function matchSegment(name: string, pattern: string): boolean
    local expression = "^"
    for index = 1, #pattern do
        local character = pattern:sub(index, index)
        if character == "*" then
            expression ..= ".*"
        elseif character == "?" then
            expression ..= "."
        elseif character:match("[% ^%$%(%)%%%.%[%]%+%-]":gsub(" ", "")) then
            expression ..= "%" .. character
        else
            expression ..= character
        end
    end
    return name:match(expression .. "$") ~= nil
end

local function matches(path: { string }, pattern: { string }, position: number, index: number): boolean
    if index > #pattern then
        return position > #path
    end
    if pattern[index] == "**" then
        if matches(path, pattern, position, index + 1) then
            return true
        end
        return position <= #path and matches(path, pattern, position + 1, index)
    end
    if position > #path or not matchSegment(path[position], pattern[index]) then
        return false
    end
    return matches(path, pattern, position + 1, index + 1)
end

function Glob.Match(path: string, pattern: string): boolean
    return matches(split(path), split(pattern), 1, 1)
end

function Glob.Find(pattern: string, root: string?): { string }
    local parts = split(pattern)
    if pattern:sub(1, 1) == "/" or pattern:find("\\", 1, true) or #parts == 0 then
        error(`invalid glob: {pattern}`, 0)
    end
    for _, part in parts do
        if part == "." or part == ".." or part == "" or part:find(":", 1, true) then
            error(`invalid glob segment: {pattern}`, 0)
        end
    end

    local prefix = {}
    for _, part in parts do
        if part:find("*", 1, true) or part:find("?", 1, true) then
            break
        end
        table.insert(prefix, part)
    end

    local base = root or "."
    local results = {}
    local start = table.concat(prefix, "/")
    local maxDepth = if table.find(parts, "**") then nil else #parts

    local function visit(relative: string)
        local absolute = if relative == "" then base else `{base}/{relative}`
        local metadata = Fs.metadata(absolute)
        if metadata.kind == "symlink" then
            error(`symlink in glob scope: {relative}`, 0)
        end
        if relative ~= "" and Glob.Match(relative, pattern) then
            table.insert(results, relative)
        end
        if metadata.kind ~= "dir" then
            return
        end
        if maxDepth and #split(relative) >= maxDepth then
            return
        end
        local children = Fs.readDir(absolute)
        table.sort(children)
        for _, child in children do
            visit(if relative == "" then child else `{relative}/{child}`)
        end
    end

    local absolute = if start == "" then base else `{base}/{start}`
    if Fs.metadata(absolute).exists then
        visit(start)
    end
    table.sort(results)
    return results
end

return Glob
