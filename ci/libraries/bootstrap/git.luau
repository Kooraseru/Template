-- ci/libraries/bootstrap/git.luau
--!strict

local Git = {}

--# Modules

local Process = require("@lune/process")
local Task = require("@lune/task")

--# Functions

function Git.Bytes(arguments: { string }, cwd: string?, env: { [string]: string }?): string
	local result = Process.exec("git", arguments, { cwd = cwd, env = env })
	assert(result.ok, "Git operation failed: " .. result.stderr)

	return result.stdout
end

function Git.Text(arguments: { string }, cwd: string?, env: { [string]: string }?): string
	return (Git.Bytes(arguments, cwd, env):gsub("%s+$", ""))
end

function Git.FullSHA(value: unknown): string
	assert(type(value) == "string" and #value == 40 and value:match("^[a-f0-9]+$"), "full source SHA required")

	return value
end

function Git.Blobs(objects: { string }, cwd: string?): { string }
	if #objects == 0 then
		return {}
	end

	for _, oid in objects do
		Git.FullSHA(oid)
	end

	local child = Process.create("git", { "cat-file", "--batch" }, { cwd = cwd })
	Task.spawn(function()
		child.stdin:write(table.concat(objects, "\n") .. "\n")
		child.stdin:close()
	end)
	local bytes = child.stdout:readToEnd()
	local errors = child.stderr:readToEnd()
	assert(child:status().ok, "cannot read tracked blobs: " .. errors)
	local cursor = 1
	local result = {}

	for _, requested in objects do
		local finish = assert((bytes:find("\n", cursor, true)), "missing Git blob header")
		local oid, sizeText = bytes:sub(cursor, finish - 1):match("^([a-f0-9]+) blob (%d+)$")
		assert(oid == requested and sizeText, "unexpected Git blob response")
		local size = assert(tonumber(sizeText))
		cursor = finish + 1
		assert(
			cursor + size <= #bytes and bytes:sub(cursor + size, cursor + size) == "\n",
			"truncated Git blob payload"
		)
		table.insert(result, bytes:sub(cursor, cursor + size - 1))
		cursor += size + 1
	end

	assert(cursor == #bytes + 1, "extra Git blob response data")

	return result
end

return Git
