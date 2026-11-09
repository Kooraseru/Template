-- .github/ci/components/distribution/releases/build/releaseBuilder.luau
--!strict

local Fs = require("@std/fs")
local Process = require("@lute/process")
local Json = require("@formats/json")
local Glob = require("@ci/bootstrap/discovery/glob")
local ConflictPolicy = require("@ci/integrations/github/publication/conflictPolicy")
local ReleaseAssets = require("./releaseAssets")

local CONFIG_PATH = ".github/distribution/releases/settings.json"
local RECORD_ROOT = ".github/distribution/releases"
local OUTPUT_ROOT = "build/github/releases"

type ReleaseRecord = {
	assetPatterns: unknown,
	version: string,
	tag: string,
	type: string,
	channel: string,
	prerelease: boolean,
	commit: string,
	previousTag: string?,
	notes: string?,
}

type ReleaseIndexEntry = {
	assets: { ReleaseAssets.Asset },
	version: string,
	tag: string,
	type: string,
	channel: string,
	prerelease: boolean,
	commit: string,
	previousTag: string?,
	notes: string?,
}

type ReleaseInput = { path: string, directory: string, sequence: number, value: { [string]: unknown } }

local ReleaseBuilder = {}
ReleaseBuilder.__index = ReleaseBuilder

export type ReleaseBuilder = setmetatable<{}, typeof(ReleaseBuilder)>

local requireCommit: (string, string) -> ()
local safeNotesPath: (string) -> string

local function ensureDirectory(path: string): ()
	local metadata = (if Fs.exists(path) then Fs.type(path) else nil)
	if metadata == "link" then
		error(`refusing to write through a symlink: {path}`, 0)
	end
	if metadata == nil then
		Fs.createDirectory(path, { makeParents = true })
	elseif metadata ~= "dir" then
		error(`expected a directory at {path}`, 0)
	end
end

local function validVersion(versionType: string, version: string, options: { [string]: unknown }): boolean
	if versionType == "marketing" then
		return version ~= "" and not version:find("[/\\\\:]", 1) and not version:find("..", 1, true)
	elseif versionType == "sequential" then
		return version:match("^%d+$") ~= nil or version:match("^build%.%d+$") ~= nil or version:match("^r%d+$") ~= nil
	elseif versionType == "major_minor" then
		return version:match("^%d+%.%d+$") ~= nil or version:match("^%d+%.%d+%-pre%.%d+$") ~= nil
	elseif versionType == "calver" then
		return version:match("^%d%d%d%d%.%d%d?$") ~= nil
			or version:match("^%d%d%d%d%.%d%d?%.%d%d?$") ~= nil
			or version:match("^%d%d%.%d%d?$") ~= nil
			or version:match("^%d%d%d%d%.%d+$") ~= nil
	elseif versionType == "git" then
		return version:match("^%x%x%x%x%x%x%x+$") ~= nil
			or version:match("^[%w_.%-]+%-%x%x%x%x%x%x%x+$") ~= nil
			or version:match("^v?%d+%.%d+%.%d+%-%d+-g%x%x%x%x%x%x%x+$") ~= nil
			or version:match("^r%d+$") ~= nil
	elseif versionType == "date_build" then
		return version:match("^%d%d%d%d%.%d%d%.%d%d%.%d+$") ~= nil
			or version:match("^%d%d%d%d%.%d%d%.%d%d%-build%.%d+$") ~= nil
			or version:match("^%d%d%d%d%d%d%d%d%.%d+$") ~= nil
	elseif versionType == "compatibility" then
		return version:match("^v%d+%-api%d+$") ~= nil
			or version:match("^%d+%.%d+%-abi%d+$") ~= nil
			or version:match("^%d%d%d%d%.%d%d?%-protocol%d+$") ~= nil
	elseif versionType == "release_train" then
		return version:match("^R%d%d%d%d%.%d%d?$") ~= nil
			or version:match("^%d%d%d%d%.Q[1-4]$") ~= nil
			or version:match("^Release %d+$") ~= nil
			or version:match("^%d%d%d%d%.%d%d?%-LTS$") ~= nil
	elseif versionType == "epoch" then
		local epoch, remainder = version:match("^(%d+):(.+)$")
		return epoch ~= nil and remainder ~= nil and validVersion("semver", remainder, options)
	elseif versionType ~= "semver" then
		return false
	end

	local core = version
	local build = core:find("+", 1, true)
	if build then
		if options.allow_build_metadata ~= true or build == #core then
			return false
		end
		core = core:sub(1, build - 1)
	end
	local major, minor, patch = core:match("^(%d+)%.(%d+)%.(%d+)$")
	local preMajor, preMinor, prePatch, identifier, preNumber = core:match("^(%d+)%.(%d+)%.(%d+)%-([%w%-]+)%.(%d+)$")
	if not (major and minor and patch) and not (preMajor and preMinor and prePatch and identifier and preNumber) then
		return false
	end
	local parts = if major
			and minor
			and patch
		then { major, minor, patch }
		else { preMajor, preMinor, prePatch, preNumber }
	for _, part in parts do
		if part and #part > 1 and part:sub(1, 1) == "0" then
			return false
		end
	end
	if identifier and options.prerelease_identifier and identifier ~= options.prerelease_identifier then
		return false
	end
	return true
end

local function resolveReference(reference: string, label: string): string
	local result = Process.run({ "git",  "rev-parse", "--verify", reference .. "^{commit}" })
	if not result.ok then
		error(`{CONFIG_PATH}: unable to resolve {label} Git reference {reference}`, 0)
	end
	reference = result.stdout:gsub("%s+$", "")
	requireCommit(reference, label)
	return reference
end

local function decodeRecords(): ({ ReleaseRecord }, ConflictPolicy.Policy)
	local configuration = Json.record(Json.decode(Fs.readFileToString(CONFIG_PATH)))
	if type(configuration) ~= "table" or type(configuration.release) ~= "table" then
		error(`{CONFIG_PATH}: expected a [release] table`, 0)
	end
	local shared = Json.record(configuration.release)
	local format = shared.format
	if type(format) ~= "string" then
		error(`{CONFIG_PATH}: release.format must be a version format name`, 0)
	end
	local options = shared
	local sharedSource = shared.source
	if sharedSource ~= nil and type(sharedSource) ~= "string" then
		error(`{CONFIG_PATH}: release.source must be a Git reference`, 0)
	end
	sharedSource = sharedSource or "HEAD"
	local records: { ReleaseRecord } = {}
	local versions: { [string]: boolean } = {}
	local sequences: { [number]: boolean } = {}
	local entries: { ReleaseInput } = {}
	for _, directory in Glob.Find(`{RECORD_ROOT}/*`) do
		local metadata = (if Fs.exists(directory) then Fs.type(directory) else nil)
		if metadata == "link" then
			error(`{directory}: release records cannot be symlinks`, 0)
		end
		if not (Fs.exists(directory) and Fs.type(directory) == "dir") then
			continue
		end
		local identity = directory:match("([^/]+)$")
		if not identity or not identity:match("^[%w][%w_.-]*$") then
			error(`{directory}: invalid release record directory name`, 0)
		end
		local path = `{directory}/release.json`
		if not (Fs.exists(path) and Fs.type(path) == "file") or (if Fs.exists(path) then Fs.type(path) else nil) == "link" then
			error(`{path}: expected a regular release record`, 0)
		end
		local value = Json.record(Json.decode(Fs.readFileToString(path)))
		if type(value) ~= "table" then
			error(`{path}: expected a release object`, 0)
		end
		local sequence = value.sequence
		if type(sequence) ~= "number" or sequence < 1 or sequence % 1 ~= 0 then
			error(`{path}: sequence must be a positive integer`, 0)
		end
		if sequences[sequence] then
			error(`{path}: duplicate release sequence {sequence}`, 0)
		end
		sequences[sequence] = true
		table.insert(entries, { path = path, directory = identity, sequence = sequence, value = value })
	end
	table.sort(entries, function(a: ReleaseInput, b: ReleaseInput)
		return a.sequence < b.sequence
	end)
	for _, entry in entries do
		local value = entry.value
		local recordPath = entry.path
		local version = value.version
		local tag = value.tag or version
		local commit = value.source
		if type(version) ~= "string" or not validVersion(format, version, options) then
			error(`{recordPath}: invalid {format} release version`, 0)
		end
		if type(tag) ~= "string" or tag == "" then
			error(`{CONFIG_PATH}: release {version} tag must be a nonempty string`, 0)
		end
		local validTag = Process.run({ "git",  "check-ref-format", `refs/tags/{tag}` })
		if not validTag.ok then
			error(`{CONFIG_PATH}: release {version} has an invalid Git tag {tag}`, 0)
		end
		local prerelease = value.prerelease
		if type(prerelease) ~= "boolean" then
			error(`{CONFIG_PATH}: release {version} prerelease must be a boolean`, 0)
		end
		if versions[version] then
			error(`{CONFIG_PATH}: duplicate release version {version}`, 0)
		end
		local resolvedCommit = if commit == nil
			then resolveReference(sharedSource, `release {version} source`)
			else if type(commit) == "string"
				then resolveReference(commit, `release {version} source`)
				else error(`{CONFIG_PATH}: release {version} source must be a Git reference`, 0)
		local notesStart = value.previous_tag
		local previousTag: string? = nil
		if notesStart == "previous" then
			previousTag = if #records > 0 then records[#records].tag else nil
			if not previousTag then
				error(
					`{CONFIG_PATH}: release {version} uses previous_tag = previous but no earlier release is configured`,
					0
				)
			end
		elseif notesStart ~= nil and notesStart ~= "beginning" then
			if
				type(notesStart) ~= "string"
				or not Process.run({ "git",  "check-ref-format", `refs/tags/{notesStart}` }).ok
			then
				error(`{CONFIG_PATH}: release {version} has an invalid previous_tag`, 0)
			end
			previousTag = notesStart
		end
		if
			type(value.notes) ~= "string"
			or not string.match(value.notes, "^[%w_.-]+%.md$")
		then
			error(`{recordPath}: release record requires a notes filename`, 0)
		end
		local notes = `{entry.directory}/{value.notes}`
		safeNotesPath(notes)
		versions[version] = true
		table.insert(records, {
			version = version,
			tag = tag,
			type = format,
			channel = if prerelease then "prerelease" else "release",
			prerelease = prerelease,
			commit = resolvedCommit,
			previousTag = previousTag,
			notes = notes,
			assetPatterns = if value.assets ~= nil then value.assets else shared.assets,
		})
	end
	return records, ConflictPolicy.Parse(shared.on_existing, CONFIG_PATH)
end

requireCommit = function(commit: string, label: string): ()
	if #commit ~= 40 or not commit:match("^%x+$") then
		error(`{CONFIG_PATH}: {label} must be a full 40-character commit SHA`, 0)
	end
	local result = Process.run({ "git",  "cat-file", "-t", commit })
	if not result.ok or result.stdout:gsub("%s+$", "") ~= "commit" then
		error(`{CONFIG_PATH}: {label} is not present in the checked-out Git history: {commit}`, 0)
	end
end

safeNotesPath = function(notes: string): string
	if notes == "" or notes:find("\\", 1, true) or notes:sub(1, 1) == "/" then
		error(`{CONFIG_PATH}: unsafe release notes path {notes}`, 0)
	end
	for segment in notes:gmatch("[^/]+") do
		if segment == "." or segment == ".." then
			error(`{CONFIG_PATH}: unsafe release notes path {notes}`, 0)
		end
	end
	local source = `{RECORD_ROOT}/{notes}`
	if not (Fs.exists(source) and Fs.type(source) == "file") or (if Fs.exists(source) then Fs.type(source) else nil) == "link" then
		error(`{CONFIG_PATH}: release notes do not exist as a regular file: {source}`, 0)
	end
	return source
end

function ReleaseBuilder.new(): ReleaseBuilder
	return setmetatable({}, ReleaseBuilder)
end

function ReleaseBuilder.Run(_self: ReleaseBuilder): string?
	local records, policy = decodeRecords()
	local outputMetadata = (if Fs.exists(OUTPUT_ROOT) then Fs.type(OUTPUT_ROOT) else nil)
	if outputMetadata == "link" then
		error(`refusing to replace a symlink: {OUTPUT_ROOT}`, 0)
	elseif outputMetadata == "dir" then
		Fs.removeDirectory(OUTPUT_ROOT, { recursive = true })
	elseif outputMetadata ~= nil then
		error(`expected a directory at {OUTPUT_ROOT}`, 0)
	end
	if #records == 0 then
		print("Releases skipped: no release records")
		return "skipped"
	end
	ensureDirectory("build")
	ensureDirectory("build/github")
	ensureDirectory(OUTPUT_ROOT)

	local index: { ReleaseIndexEntry } = {}
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
		local entry = {
			assets = ReleaseAssets.Stage(release.assetPatterns, `{releaseDirectory}/assets`, release.commit),
			version = release.version,
			tag = release.tag,
			type = release.type,
			channel = release.channel,
			prerelease = release.prerelease,
			commit = release.commit,
			previousTag = release.previousTag,
			notes = notesOutput,
		}
		Fs.writeStringToFile(`{releaseDirectory}/release.json`, Json.encode(entry))
		table.insert(index, entry)
	end

	Fs.writeStringToFile(`{OUTPUT_ROOT}/index.json`, Json.encode({ onExisting = policy, releases = index }))
	print(`Staged {#records} release records into {OUTPUT_ROOT}`)
	return nil
end

return ReleaseBuilder
