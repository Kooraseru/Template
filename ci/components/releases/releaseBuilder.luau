-- ci/components/releases/releaseBuilder.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")

const CONFIG_PATH = "config/releases.toml"
const RECORD_ROOT = "content/releases/records"
const OUTPUT_ROOT = "build/repo/releases"

type ReleaseRecord = { version: string, commit: string, from: string?, notes: string? }

local ReleaseBuilder = {}
ReleaseBuilder.__index = ReleaseBuilder

export type ReleaseBuilder = setmetatable<{}, typeof(ReleaseBuilder)>

local function ensureDirectory(path: string): ()
	local metadata = Fs.metadata(path)
	if metadata.kind == "symlink" then
		error(`refusing to write through a symlink: {path}`, 0)
	end
	if not metadata.exists then
		Fs.writeDir(path)
	elseif metadata.kind ~= "dir" then
		error(`expected a directory at {path}`, 0)
	end
end

local function validVersion(version: string): boolean
	local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
	local preMajor, preMinor, prePatch, preNumber = version:match("^(%d+)%.(%d+)%.(%d+)%-pre%.(%d+)$")
	local parts: { string }
	if major and minor and patch then
		parts = { major, minor, patch }
	elseif preMajor and preMinor and prePatch and preNumber then
		parts = { preMajor, preMinor, prePatch, preNumber }
	else
		return false
	end
	for _, part in parts do
		if #part > 1 and part:sub(1, 1) == "0" then
			return false
		end
	end
	return true
end

local function requireCommit(commit: string, label: string): ()
	if #commit ~= 40 or not commit:match("^%x+$") then
		error(`{CONFIG_PATH}: {label} must be a full 40-character commit SHA`, 0)
	end
	local result = Process.exec("git", { "cat-file", "-t", commit })
	if not result.ok or result.stdout:gsub("%s+$", "") ~= "commit" then
		error(`{CONFIG_PATH}: {label} is not present in the checked-out Git history: {commit}`, 0)
	end
end

local function safeNotesPath(notes: string): string
	if notes == "" or notes:find("\\", 1, true) or notes:sub(1, 1) == "/" then
		error(`{CONFIG_PATH}: unsafe release notes path {notes}`, 0)
	end
	for segment in notes:gmatch("[^/]+") do
		if segment == "." or segment == ".." then
			error(`{CONFIG_PATH}: unsafe release notes path {notes}`, 0)
		end
	end
	local source = `{RECORD_ROOT}/{notes}`
	if not Fs.isFile(source) or Fs.metadata(source).kind == "symlink" then
		error(`{CONFIG_PATH}: release notes do not exist as a regular file: {source}`, 0)
	end
	return source
end

local function decodeRecords(): { ReleaseRecord }
	local configuration = Serde.decode("toml", Fs.readFile(CONFIG_PATH))
	if type(configuration) ~= "table" or type(configuration.releases) ~= "table" then
		error(`{CONFIG_PATH}: expected a releases array`, 0)
	end

	local records: { ReleaseRecord } = {}
	local versions: { [string]: boolean } = {}
	for index, value in configuration.releases do
		if type(index) ~= "number" or type(value) ~= "table" then
			error(`{CONFIG_PATH}: release entries must be tables`, 0)
		end
		local version = value.version
		local commit = value.commit
		local from = value.from
		local notes = value.notes
		if type(version) ~= "string" or not validVersion(version) then
			error(`{CONFIG_PATH}: release {index} has an invalid semantic version`, 0)
		end
		if type(commit) ~= "string" then
			error(`{CONFIG_PATH}: release {version} requires a source commit SHA`, 0)
		end
		if versions[version] then
			error(`{CONFIG_PATH}: duplicate release version {version}`, 0)
		end
		requireCommit(commit, `release {version} commit`)
		if from ~= nil and type(from) ~= "string" then
			error(`{CONFIG_PATH}: release {version} from must be a full SHA or beginning`, 0)
		end
		if from and from ~= "beginning" then
			requireCommit(from, `release {version} from`)
			local ancestry = Process.exec("git", { "merge-base", "--is-ancestor", from, commit })
			if not ancestry.ok then
				error(`{CONFIG_PATH}: release {version} from commit is not an ancestor of its source commit`, 0)
			end
		end
		if notes ~= nil and type(notes) ~= "string" then
			error(`{CONFIG_PATH}: release {version} notes must name a Markdown record`, 0)
		end
		if notes and not notes:match("%.md$") then
			error(`{CONFIG_PATH}: release {version} notes must be a Markdown file`, 0)
		end
		if notes then
			safeNotesPath(notes)
		end
		versions[version] = true
		table.insert(records, { version = version, commit = commit, from = from, notes = notes })
	end
	return records
end

function ReleaseBuilder.new(): ReleaseBuilder
	return setmetatable({}, ReleaseBuilder)
end

function ReleaseBuilder.Run(_self: ReleaseBuilder): ()
	local records = decodeRecords()
	local outputMetadata = Fs.metadata(OUTPUT_ROOT)
	if outputMetadata.kind == "symlink" then
		error(`refusing to replace a symlink: {OUTPUT_ROOT}`, 0)
	elseif outputMetadata.kind == "dir" then
		Fs.removeDir(OUTPUT_ROOT)
	elseif outputMetadata.exists then
		error(`expected a directory at {OUTPUT_ROOT}`, 0)
	end
	ensureDirectory("build")
	ensureDirectory("build/repo")
	ensureDirectory(OUTPUT_ROOT)

	local index: { { version: string, commit: string, from: string?, notes: string? } } = {}
	for _, release in records do
		local releaseDirectory = `{OUTPUT_ROOT}/{release.version}`
		ensureDirectory(releaseDirectory)
		local notesOutput: string? = nil
		if release.notes then
			local source = safeNotesPath(release.notes)
			local notesName = release.notes:match("([^/]+)$")
			if not notesName then
				error(`invalid release notes path: {release.notes}`, 0)
			end
			Fs.copy(source, `{releaseDirectory}/{notesName}`)
			notesOutput = `{release.version}/{notesName}`
		end
		local entry = { version = release.version, commit = release.commit, from = release.from, notes = notesOutput }
		Fs.writeFile(`{releaseDirectory}/release.json`, Serde.encode("json", entry))
		table.insert(index, entry)
	end

	Fs.writeFile(`{OUTPUT_ROOT}/index.json`, Serde.encode("json", { releases = index }))
	print(`Staged {#records} release records into {OUTPUT_ROOT}`)
end

return ReleaseBuilder
