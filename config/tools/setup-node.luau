-- config/tools/setup-node.luau
--!strict

local SetupNode = {}

--# Modules

local Fs = require("@lune/fs")
local Net = require("@lune/net")
local Process = require("@lune/process")
local Serde = require("@lune/serde")

--# Types

export type Platform = {
	file: string,
	sha256: string,
}

export type Definition = {
	version: string,
	url: string,
	platforms: { [string]: Platform },
}

export type Installation = {
	version: string,
	directory: string,
}

--# Constants

local DEFINITION_PATH = "config/tools/ruleset.json"

--# Helpers

local function readObject(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "expected Node configuration object")

	local result: { [string]: unknown } = {}

	for key, child in pairs(value) do
		assert(type(key) == "string", "expected Node configuration field name")

		result[key] = child
	end

	return result
end

local function readString(record: { [string]: unknown }, key: string): string
	local value = record[key]

	assert(type(value) == "string" and value ~= "", "missing or invalid Node configuration field: " .. key)

	return value
end

local function extractArchive(platform: Platform, archive: string, destination: string): string
	Fs.writeDir(destination)

	local result: Process.Execution
	local executableDirectory: string

	if Process.os == "windows" then
		result = Process.exec("unzip", { "-o", archive, "-d", destination })
		executableDirectory = destination .. "/" .. platform.file:gsub("%.zip$", "")
	else
		result = Process.exec("tar", { "-xf", archive, "--strip-components=1", "-C", destination })
		executableDirectory = destination .. "/bin"
	end

	assert(result.ok, "Node extraction failed: " .. result.stderr)

	return executableDirectory
end

local function appendWorkflowPath(output: string, directory: string)
	local existing = if Fs.isFile(output) then Fs.readFile(output) else ""

	local separator = if existing ~= "" and existing:sub(-1) ~= "\n" then "\n" else ""

	Fs.writeFile(output, existing .. separator .. directory .. "\n")
end

--# Functions

-- Decoded fields are validated and copied into a typed contract before installation.
function SetupNode.ReadDefinition(path: string?): Definition
	local source = Fs.readFile(path or DEFINITION_PATH)
	local raw: unknown = Serde.decode("json", source)
	local document = if path then readObject(raw) else readObject(readObject(readObject(raw).node).definition)
	local platforms: { [string]: Platform } = {}

	for name, value in pairs(readObject(document.platforms)) do
		local entry = readObject(value)
		local file = readString(entry, "file")
		local checksum = readString(entry, "sha256")

		assert(file:match("^[%w%.%-]+$") and file ~= "." and file ~= "..", "invalid Node archive filename")
		assert(#checksum == 64 and checksum:match("^[a-f0-9]+$"), "invalid Node archive checksum")

		platforms[name] = {
			file = file,
			sha256 = checksum,
		}
	end

	return {
		version = readString(document, "version"),
		url = readString(document, "url"),
		platforms = platforms,
	}
end

-- Uses the runner temporary directory and exports PATH only after checksum verification.
-- Requiring this module performs no download, extraction or workflow-file mutation.
function SetupNode.Run(): Installation
	local temporaryDirectory = Process.env.RUNNER_TEMP
	local workflowPath = Process.env.GITHUB_PATH

	assert(temporaryDirectory ~= nil and temporaryDirectory ~= "", "missing runner temporary directory")
	assert(workflowPath ~= nil and workflowPath ~= "", "missing workflow path file")

	local definition = SetupNode.ReadDefinition()
	local platformName = Process.os .. "-" .. Process.arch
	local platform = definition.platforms[platformName]

	assert(platform ~= nil, "unsupported Node platform: " .. platformName)

	local root = temporaryDirectory .. "/ci-node"
	local archive = root .. "/" .. platform.file
	local response = Net.request(definition.url .. platform.file)

	assert(response.ok, "Node download failed")
	assert(Serde.hash("sha256", response.body) == platform.sha256, "Node checksum mismatch")

	Fs.writeDir(root)
	Fs.writeFile(archive, response.body)

	local directory = extractArchive(platform, archive, root .. "/runtime")

	appendWorkflowPath(workflowPath, directory)

	return {
		version = definition.version,
		directory = directory,
	}
end

return SetupNode
