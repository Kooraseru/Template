-- ci/publication/releases/notes.luau
--!strict

local Notes = {}

--# Modules

local Json = require("../../utilities/json")
local Fs = require("@lune/fs")
local C = require("../../utilities/canonical")
local D = require("../../utilities/documents")
local History = require("./history")
local Client = require("./client")

--# Functions

function Notes.Escape(value: string): string
	return (value:gsub("[\\`*_{}%[%]()<>#!|]", "\\%0"):gsub("[\r\n]", " "))
end

function Notes.Build(selection: C.Value, data: History.Data, repoURL: string, api: Client.API?): string
	local linked: { [number]: C.Value } = {}
	local covered: { [string]: boolean } = {}
	local inRange: { [string]: boolean } = {}
	for _, commit in data.commits do
		inRange[D.Text(commit, "sha")] = true
	end
	if api then
		for _, commit in data.commits do
			for _, pr in api.Pages("/commits/" .. D.Text(commit, "sha") .. "/pulls") do
				local base = D.Required(pr, "base")
				local merged = D.Get(pr, "merged_at")
				if
					Json.Truthy(merged)
					and D.Get(base, "ref") == "source"
					and D.Get(D.Required(base, "repo"), "html_url") == repoURL
					and inRange[D.Text(pr, "merge_commit_sha")]
				then
					linked[D.Number(pr, "number")] = pr
					covered[D.Text(commit, "sha")] = true
				end
			end
		end
	end
	local numbers: { number } = {}
	for number in linked do
		table.insert(numbers, number)
	end
	table.sort(numbers)
	local lines: { string } = {}
	for _, number in numbers do
		local pr = linked[number]
		table.insert(
			lines,
			"- "
				.. Notes.Escape(D.Text(pr, "title"))
				.. " by @"
				.. Notes.Escape(D.Text(D.Required(pr, "user"), "login"))
				.. " in [#"
				.. number
				.. "]("
				.. repoURL
				.. "/pull/"
				.. number
				.. ")"
		)
	end
	local direct: { C.Value } = {}
	for _, commit in data.commits do
		if not covered[D.Text(commit, "sha")] then
			table.insert(direct, commit)
		end
	end
	local introduction = if D.Get(selection, "notes")
		then Fs.readFile(D.Text(selection, "notes")):gsub("%s+$", "") .. "\n\n"
		else ""
	local text = introduction
		.. "## What's Changed\n\n"
		.. (
			if #lines > 0
				then table.concat(lines, "\n")
				elseif #direct > 0 then "Changes were pushed directly to source."
				else "No changes in this range."
		)
	if #direct > 0 then
		local changes: { string } = {}
		local limit = D.Number(D.Required(D.Read("ci/publication/releases/ruleset.json"), "rules"), "body_commit_limit")
		for index, commit in direct do
			if index <= limit then
				table.insert(
					changes,
					"- [" .. Notes.Escape(D.Text(commit, "subject")) .. "](" .. D.Text(commit, "url") .. ")"
				)
			end
		end
		text ..= "\n\n<details>\n<summary>Direct changes (" .. #direct .. ")</summary>\n\n" .. table.concat(
			changes,
			"\n"
		) .. "\n\n</details>"
	end
	local first, source = D.Text(selection, "from"), D.Text(selection, "source_sha")
	local compare = if first == "beginning"
		then repoURL .. "/commits/" .. source
		else repoURL .. "/compare/" .. first .. "..." .. source
	text ..= "\n\n**Full Changelog**: [View changes](" .. compare .. ")\n"
	if #data.coauthors > 0 then
		local authors = {}
		for _, name in data.coauthors do
			table.insert(authors, "Co-authored-by: " .. Notes.Escape(name))
		end
		text ..= "\n---\n\n" .. table.concat(authors, "  \n") .. "\n"
	end
	return text
end

return Notes
