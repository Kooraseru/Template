-- ci/utilities/bundles.luau
--!strict

local Bundles = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local C = require("./canonical")
local D = require("./documents")
local Json = require("./json")
local Commands = require("./commands")
local Shape = require("./shape")

--# Functions

function Bundles.Manifest(root: string): C.Array
	local files: { C.Value } = {}
	local function walk(directory: string, prefix: string)
		assert(Fs.metadata(directory).kind == "dir", "bundle root must be a directory")
		local names = Fs.readDir(directory)
		table.sort(names)
		for _, name in names do
			local path = Shape.Relative(prefix .. name)
			local full = directory .. "/" .. name
			local kind = Fs.metadata(full).kind
			if kind == "dir" then
				walk(full, path .. "/")
			else
				assert(kind == "file", "bundle links and special files are forbidden")
				table.insert(files, C.Object({ path = path, sha256 = Serde.hash("sha256", Fs.readFile(full)) }))
			end
		end
	end
	walk(root, "")
	return C.Array(files)
end

function Bundles.VerifyFiles(root: string, expected: C.Value)
	local expectedByPath: { [string]: C.Value } = {}
	for _, file in Json.Array(expected) do
		local path = Shape.Relative(D.Text(file, "path"))
		assert(not expectedByPath[path], "duplicate manifest path")
		expectedByPath[path] = D.Required(file, "sha256")
	end
	for _, file in Bundles.Manifest(root).items do
		local path = D.Text(file, "path")
		assert(D.Equal(expectedByPath[path], D.Get(file, "sha256")), "bundle files or checksums differ: " .. path)
		expectedByPath[path] = nil
	end
	assert(next(expectedByPath) == nil, "bundle file missing")
end

function Bundles.Normalize(root: string, name: string, marker: string)
	Shape.Relative(name)
	if Fs.isDir(root .. "/" .. name) or not Fs.isFile(root .. "/" .. marker) then
		return
	end
	local names = Fs.readDir(root)
	Fs.writeDir(root .. "/" .. name)
	for _, entry in names do
		Fs.move(root .. "/" .. entry, root .. "/" .. name .. "/" .. entry)
	end
end

function Bundles.Unpack(archive: string, root: string)
	for line in Commands.Run("tar", { "-tzf", archive }):gmatch("[^\r\n]+") do
		if line ~= "./" then
			Shape.Relative((line:gsub("^%./", ""):gsub("/$", "")))
		end
	end
	for line in Commands.Run("tar", { "-tvzf", archive }):gmatch("[^\r\n]+") do
		assert(line:sub(1, 1) == "-" or line:sub(1, 1) == "d", "archive links or special files forbidden")
	end
	assert(not Fs.metadata(root).exists, "extraction destination must be fresh")
	Fs.writeDir(root)
	Commands.Run("tar", { "-xzf", archive, "-C", root })
	Bundles.Manifest(root)
end

return Bundles
