-- ci/bootstrap/glob.luau
--!strict

local Fs = require("@lune/fs")

local Glob = {}

local function split(path: string): { string }
	local parts: { string } = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    return parts
end

-- Reuse a compiled segment pattern across a glob walk instead of rebuilding
-- the same Lua expression for every matching file or directory.
local expressions: { [string]: string } = {}

local function matchSegment(name: string, pattern: string): boolean
    local expression = expressions[pattern]
    if not expression then
		local fragments: { string } = { "^" }
        for index = 1, #pattern do
            local character = pattern:sub(index, index)
            if character == "*" then
                table.insert(fragments, ".*")
            elseif character == "?" then
                table.insert(fragments, ".")
            elseif ("^$()%.[]+-"):find(character, 1, true) then
                table.insert(fragments, "%" .. character)
            else
                table.insert(fragments, character)
            end
        end
        table.insert(fragments, "$")
        expression = table.concat(fragments)
        expressions[pattern] = expression
    end
    return name:match(expression) ~= nil
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

	local prefix: { string } = {}
    for _, part in parts do
        if part:find("*", 1, true) or part:find("?", 1, true) then
            break
        end
        table.insert(prefix, part)
    end

    local base = root or "."
	local results: { string } = {}
    local start = table.concat(prefix, "/")
	local maxDepth: number? = if table.find(parts, "**") then nil else #parts

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

-- Two declared output globs must not be able to claim the same path.
-- Both * / ? inside segments and ** spanning segments are considered.
local function segmentOverlaps(left: string, right: string): boolean
	local visited: { [string]: boolean } = {}
    local function visit(i: number, j: number): boolean
        local key = `{i}:{j}`
        if visited[key] then
            return false
        end
        visited[key] = true
        if i > #left and j > #right then
            return true
        end
        local a = if i <= #left then left:sub(i, i) else nil
        local b = if j <= #right then right:sub(j, j) else nil
        if a == "*" and visit(i + 1, j) then
            return true
        end
        if b == "*" and visit(i, j + 1) then
            return true
        end
        if a and b and (a == "*" or b == "*" or a == "?" or b == "?" or a == b) then
            return visit(if a == "*" then i else i + 1, if b == "*" then j else j + 1)
        end
        return false
    end
    return visit(1, 1)
end

function Glob.Overlaps(left: string, right: string): boolean
	local one = split(left)
	local two = split(right)
    local visited: { [string]: boolean } = {}
    local function visit(i: number, j: number): boolean
        local key = `{i}:{j}`
        if visited[key] then
            return false
        end
        visited[key] = true
        if i > #one and j > #two then
            return true
        end
        local a = one[i]
        local b = two[j]
        if a == "**" and visit(i + 1, j) then
            return true
        end
        if b == "**" and visit(i, j + 1) then
            return true
        end
        if a and b and (a == "**" or b == "**" or segmentOverlaps(a, b)) then
            return visit(if a == "**" then i else i + 1, if b == "**" then j else j + 1)
        end
        return false
    end
    return visit(1, 1)
end

return Glob
