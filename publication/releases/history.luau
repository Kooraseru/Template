-- publication/releases/history.luau
--!strict

local History = {}

--# Modules

local Json = require("../../libraries/bootstrap/json")
local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Regex = require("@lune/regex")
local C = require("../../libraries/bootstrap/canonical")
local D = require("../../libraries/bootstrap/documents")
local Git = require("../../libraries/bootstrap/git")
local Commands = require("../../libraries/bootstrap/commands")

--# Types

export type Data = {
	commits: { C.Value },
	context: C.Value?,
	coauthors: { string },
	contributors: { string },
	stats: string,
	shortstat: string,
}

--# Functions

function History.Read(selection: C.Value, repository: string?, repoURL: string?): Data
	local cwd = repository or "."
	local url = repoURL or ""
	local source = D.Text(selection, "source_sha")
	local first = D.Text(selection, "from")
	Git.FullSHA(source)
	if first ~= "beginning" then
		Git.FullSHA(first)
	end
	local range = if first == "beginning" then source else first .. ".." .. source
	local commits: { C.Value } = {}
	local identities: { string } = {}
	local trailers: { [number]: boolean } = {}
	local rules = D.Required(D.Read("publication/releases/ruleset.json"), "rules")
	for sha in Git.Text({ "rev-list", "--topo-order", range }, cwd):gmatch("[^\n]+") do
		local data = Git.Text({ "show", "-s", "--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00%B", sha }, cwd)
			:split("\0")
		local parents: { C.Value } = {}
		for parent in data[2]:gmatch("%S+") do
			table.insert(parents, parent)
		end
		local body = table.concat(data, "\0", 7)
		table.insert(
			commits,
			C.Object({
				sha = data[1],
				parents = C.Array(parents),
				name = data[3],
				email = data[4],
				date = data[5],
				subject = data[6],
				body = body,
				url = url .. "/commit/" .. sha,
			})
		)
		table.insert(identities, data[3] .. " <" .. data[4] .. ">")
		for line in Commands.Run("git", { "interpret-trailers", "--parse" }, body, cwd):gmatch("[^\n]+") do
			if line:lower():match("^co%-authored%-by:") then
				local identity = line:gsub("^[^:]+:%s*", ""):gsub("%s+$", "")
				if identity:match("^.+ <[^<>%s]+>$") then
					table.insert(identities, identity)
					trailers[#identities] = true
				end
			end
		end
	end
	local mapDir = "build/tmp/mailmap/" .. source
	Fs.writeDir(mapDir)
	local mapPath = Process.cwd:gsub("\\", "/"):gsub("/$", "") .. "/" .. mapDir .. "/mailmap"
	local mailmap = Commands.Execute("git", { "show", source .. ":.mailmap" }, nil, cwd)
	Fs.writeFile(mapPath, if mailmap.ok then mailmap.stdout else "")
	local people: { [string]: string } = {}
	local coauthors: { [string]: string } = {}
	if #identities > 0 then
		local normalized = Commands.Run(
			"git",
			{ "-c", "mailmap.file=" .. mapPath, "-c", "mailmap.blob=", "check-mailmap", "--stdin" },
			table.concat(identities, "\n") .. "\n",
			mapDir,
			{ GIT_DIR = Git.Text({ "rev-parse", "--absolute-git-dir" }, cwd) }
		)
		local index = 0
		for identity in normalized:gmatch("[^\n]+") do
			index += 1
			local name, email = identity:match("^(.*) <([^<>]+)>$")
			if not name or not email then
				continue
			end
			local bot = false
			for _, pattern in D.Items(rules, "bot_patterns") do
				local expression = Regex.new("(?i)" .. Json.String(pattern))
				bot = bot or expression:isMatch(identity) or expression:isMatch(name) or expression:isMatch(email)
			end
			if not bot then
				people[email:lower()] = name
				if trailers[index] then
					coauthors[email:lower()] = name
				end
			end
		end
	end
	local labels: { [string]: { C.Value } } = {}
	for line in
		Git.Text({
			"for-each-ref",
			"--format=%(objectname)%09%(*objectname)%09%(refname)",
			"refs/heads",
			"refs/remotes",
			"refs/tags",
		}, cwd):gmatch("[^\n]+")
	do
		local parts = line:split("\t")
		local sha = if parts[2] ~= "" then parts[2] else parts[1]
		if not parts[3] or parts[3]:match("/HEAD$") then
			continue
		end
		local reference = parts[3]:gsub("^refs/heads/", ""):gsub("^refs/remotes/", ""):gsub("^refs/tags/", "")
		labels[sha] = labels[sha] or {}
		table.insert(labels[sha], reference)
	end
	for index, commit in commits do
		commits[index] = D.Set(commit, "refs", C.Array(labels[D.Text(commit, "sha")] or {}))
	end
	local context: C.Value? = nil
	if first ~= "beginning" then
		local parts = Git.Text({ "show", "-s", "--format=%H%x00%P%x00%s", first }, cwd):split("\0")
		local parents: { C.Value } = {}
		for sha in parts[2]:gmatch("%S+") do
			table.insert(parents, sha)
		end
		context = C.Object({
			sha = parts[1],
			parents = C.Array(parents),
			subject = parts[3],
			context = true,
			url = url .. "/commit/" .. parts[1],
			refs = C.Array(labels[parts[1]] or {}),
		})
	end
	local start = if first == "beginning"
		then (Commands.Run("git", { "hash-object", "-t", "tree", "--stdin" }, "", cwd):gsub("%s+$", ""))
		else first
	local names, authors = {}, {}
	for _, name in people do
		table.insert(names, name)
	end
	for _, name in coauthors do
		table.insert(authors, name)
	end
	table.sort(names)
	table.sort(authors)
	return {
		commits = commits,
		context = context,
		coauthors = authors,
		contributors = names,
		stats = Git.Text({ "diff", "--stat", start, source }, cwd),
		shortstat = Git.Text({ "diff", "--shortstat", start, source }, cwd),
	}
end

function History.Layout(rows: { C.Value }): { C.Value }
	local lanes: { C.Value } = {}
	local result: { C.Value } = {}
	for _, row in rows do
		local sha = D.Text(row, "sha")
		local lane = table.find(lanes, sha)
		local incoming = lane ~= nil
		lane = lane or table.find(lanes, C.Null) or (#lanes + 1)
		lanes[lane] = sha
		local before = C.Array(table.clone(lanes))
		lanes[lane] = C.Null
		local edges: { C.Value } = {}
		for index, rawParent in D.Items(row, "parents") do
			local parent = Json.String(rawParent)
			local destination = table.find(lanes, parent)
			if not destination then
				destination = if index == 1 and lanes[lane] == C.Null
					then lane
					else table.find(lanes, C.Null) or (#lanes + 1)
				lanes[destination] = parent
			end
			table.insert(edges, C.Object({ from = assert(lane) - 1, to = assert(destination) - 1, parent = parent }))
		end
		local after = C.Array(table.clone(lanes))
		while lanes[#lanes] == C.Null do
			table.remove(lanes)
		end
		local fields = Json.Fields(row)
		fields.lane = lane - 1
		fields.incoming = incoming
		fields.before = before
		fields.after = after
		fields.edges = C.Array(edges)
		table.insert(result, C.Object(fields))
	end
	return result
end

return History
