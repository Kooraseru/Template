-- ci/publication/releases/versions.luau
--!strict

local Versions = {}

--# Modules

local Process = require("@lune/process")
local Rules = require("../../validation/rules")
local Config = require("../../fabricator/config")
local Request = require("../../integration/request")

--# Types

export type Selection = {
	version: string,
	prerelease: boolean,
	type: string,
	source_sha: string,
	from: string,
	notes: string?,
}

--# Helpers

local function validSHA(value: unknown): boolean
	return type(value) == "string" and #value == 40 and value:match("^[a-f0-9]+$") ~= nil
end

local function ancestor(before: string, after: string, repository: string?): boolean
	return Process.exec("git", { "merge-base", "--is-ancestor", before, after }, { cwd = repository }).ok
end

--# Functions

function Versions.Parse(version: string): { version: string, prerelease: boolean, type: string }
	return Request.Version(version)
end

function Versions.Validate(raw: unknown, tip: string, repository: string?): { Selection }
	assert(validSHA(tip), "Source tip must be a full SHA")
	local document = Rules.Entries(raw)

	for key in document do
		assert(key == "releases", "Expected an explicit releases list")
	end

	local releases = Rules.Array(document.releases)
	local result: { Selection } = {}
	local seen: { [string]: boolean } = {}

	for _, entry in releases do
		local selection = Rules.Entries(entry)

		for key in selection do
			assert(type(key) == "string", "Invalid release option key")
			assert(table.find({ "version", "from", "commit", "notes" }, key), "Unknown release option")
		end

		assert(type(selection.version) == "string", "missing version")
		local version = Versions.Parse(selection.version)
		assert(not seen[version.version], "Duplicate version: " .. version.version)
		seen[version.version] = true
		local commit = selection.commit
		local from = if selection.from == nil then "beginning" else selection.from
		assert(
			type(commit) == "string" and validSHA(commit) and ancestor(commit, tip, repository),
			version.version .. " commit must be a full SHA in source history"
		)
		assert(
			type(from) == "string" and (from == "beginning" or (validSHA(from) and ancestor(from, commit, repository))),
			version.version .. " range start must be an ancestor of the selected commit"
		)

		local notes: string? = nil

		if selection.notes ~= nil then
			local value = selection.notes
			assert(type(value) == "string", "invalid release notes path")
			Config.Relative(value)
			notes = value
		end

		table.insert(result, {
			version = version.version,
			prerelease = version.prerelease,
			type = version.type,
			source_sha = commit,
			from = from,
			notes = notes,
		})
	end

	return result
end

function Versions.Select(raw: unknown, controls: Request.Controls, tip: string, repository: string?): { Selection }
	assert(
		(controls.release_version ~= nil and controls.release_version ~= "")
			== (controls.release_commit ~= nil and controls.release_commit ~= ""),
		"Release version and source commit must be supplied together"
	)
	local selected = Rules.Entries(raw)

	if controls.release_version and controls.release_version ~= "" then
		local configured: Rules.Dictionary = {}

		for _, entry in Rules.Array(selected.releases) do
			local release = Rules.Entries(entry)

			if release.version == controls.release_version then
				configured = table.clone(release)
				break
			end
		end

		configured.version = controls.release_version
		configured.commit = controls.release_commit
		selected = { releases = { configured } }
	end

	local releases = Versions.Validate(selected, tip, repository)

	if controls.release_output and controls.release_output:match("^Publish ") then
		local matching = {}

		for _, release in releases do
			if controls.release_output == "Publish " .. release.type then
				table.insert(matching, release)
			end
		end

		assert(#matching > 0, "No explicit versions match the selected public release type")
		return matching
	end

	return releases
end

return Versions
