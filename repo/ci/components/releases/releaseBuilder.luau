-- repo/ci/components/releases/releaseBuilder.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local ConflictPolicy = require("@ci/github/conflictPolicy")

const CONFIG_PATH = "repo/content/releases/releases.toml"
const RECORD_ROOT = "repo/content/releases/records"
const OUTPUT_ROOT = "build/repo/releases"

type ReleaseRecord = {
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
	version: string,
	tag: string,
	type: string,
	channel: string,
	prerelease: boolean,
	commit: string,
	previousTag: string?,
	notes: string?,
}

local ReleaseBuilder = {}
ReleaseBuilder.__index = ReleaseBuilder

export type ReleaseBuilder = setmetatable<{}, typeof(ReleaseBuilder)>

local requireCommit: (string, string) -> ()
local safeNotesPath: (string) -> string

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

local function validVersion(versionType: string, version: string, options: { [string]: any }): boolean
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
	local result = Process.exec("git", { "rev-parse", "--verify", reference .. "^{commit}" })
	if not result.ok then
		error(`{CONFIG_PATH}: unable to resolve {label} Git reference {reference}`, 0)
	end
	reference = result.stdout:gsub("%s+$", "")
	requireCommit(reference, label)
	return reference
end

local function decodeRecords(): ({ ReleaseRecord }, ConflictPolicy.Policy)
	local configuration = Serde.decode("toml", Fs.readFile(CONFIG_PATH))
	if type(configuration) ~= "table" or type(configuration.release) ~= "table" then
		error(`{CONFIG_PATH}: expected a [release] table`, 0)
	end
	local shared = configuration.release
	local formatSelection = shared.format
	local format = if type(formatSelection) == "table" then formatSelection.type else nil
	local formats = shared.formats
	local channels = shared.channels
	if type(format) ~= "string" or type(formats) ~= "table" or type(formats[format]) ~= "table" then
		error(`{CONFIG_PATH}: release.format must select a configured [release.formats.<format>] table`, 0)
	end
	if type(channels) ~= "table" then
		error(`{CONFIG_PATH}: configure release channels under [release.channels.<name>]`, 0)
	end
	local options = formats[format]
	local entries = options.entries
	if type(entries) ~= "table" then
		error(`{CONFIG_PATH}: release format {format} requires an entries array`, 0)
	end
	local sharedSource = shared.source
	if sharedSource ~= nil and type(sharedSource) ~= "string" then
		error(`{CONFIG_PATH}: release.source must be a Git reference`, 0)
	end
	sharedSource = sharedSource or "HEAD"
	local sharedNotes = shared.notes
	if sharedNotes ~= nil and (type(sharedNotes) ~= "string" or not sharedNotes:match("%.md$")) then
		error(`{CONFIG_PATH}: release.notes must name a Markdown record`, 0)
	end
	if sharedNotes then
		safeNotesPath(sharedNotes)
	end

	local records: { ReleaseRecord } = {}
	local versions: { [string]: boolean } = {}
	for index, value in entries do
		if type(index) ~= "number" or type(value) ~= "table" then
			error(`{CONFIG_PATH}: release entries must be tables`, 0)
		end
		local version = value.version
		local tag = value.tag or version
		local channel = value.channel
		local commit = value.source
		if type(version) ~= "string" or not validVersion(format, version, options) then
			error(`{CONFIG_PATH}: {format} release entry {index} has an invalid version`, 0)
		end
		if type(tag) ~= "string" or tag == "" then
			error(`{CONFIG_PATH}: release {version} tag must be a nonempty string`, 0)
		end
		local validTag = Process.exec("git", { "check-ref-format", `refs/tags/{tag}` })
		if not validTag.ok then
			error(`{CONFIG_PATH}: release {version} has an invalid Git tag {tag}`, 0)
		end
		if type(channel) ~= "string" or type(channels[channel]) ~= "table" then
			error(`{CONFIG_PATH}: release {version} selects undeclared channel {tostring(channel)}`, 0)
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
				or not Process.exec("git", { "check-ref-format", `refs/tags/{notesStart}` }).ok
			then
				error(`{CONFIG_PATH}: release {version} has an invalid previous_tag`, 0)
			end
			previousTag = notesStart
		end
		local prerelease = channels[channel].prerelease
		if prerelease ~= nil and type(prerelease) ~= "boolean" then
			error(`{CONFIG_PATH}: channel {channel} prerelease must be a boolean`, 0)
		end
		versions[version] = true
		table.insert(records, {
			version = version,
			tag = tag,
			type = format,
			channel = channel,
			prerelease = prerelease == true,
			commit = resolvedCommit,
			previousTag = previousTag,
			notes = sharedNotes,
		})
	end
	return records, ConflictPolicy.Parse(shared.on_existing, CONFIG_PATH)
end

requireCommit = function(commit: string, label: string): ()
	if #commit ~= 40 or not commit:match("^%x+$") then
		error(`{CONFIG_PATH}: {label} must be a full 40-character commit SHA`, 0)
	end
	local result = Process.exec("git", { "cat-file", "-t", commit })
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
	if not Fs.isFile(source) or Fs.metadata(source).kind == "symlink" then
		error(`{CONFIG_PATH}: release notes do not exist as a regular file: {source}`, 0)
	end
	return source
end

function ReleaseBuilder.new(): ReleaseBuilder
	return setmetatable({}, ReleaseBuilder)
end

function ReleaseBuilder.Run(_self: ReleaseBuilder): ()
	local records, policy = decodeRecords()
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
			version = release.version,
			tag = release.tag,
			type = release.type,
			channel = release.channel,
			prerelease = release.prerelease,
			commit = release.commit,
			previousTag = release.previousTag,
			notes = notesOutput,
		}
		Fs.writeFile(`{releaseDirectory}/release.json`, Serde.encode("json", entry))
		table.insert(index, entry)
	end

	Fs.writeFile(`{OUTPUT_ROOT}/index.json`, Serde.encode("json", { onExisting = policy, releases = index }))
	print(`Staged {#records} release records into {OUTPUT_ROOT}`)
end

return ReleaseBuilder
