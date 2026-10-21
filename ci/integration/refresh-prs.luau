-- ci/integration/refresh-prs.luau
--!strict

local RefreshPRs = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local GitHub = require("../libraries/bootstrap/github")
local Request = require("./request")
local Rules = require("../libraries/registry/rules")
local Base64 = require("../libraries/bootstrap/base64")

--# Types

type PullRequest = { number: number, title: string, state: string? }

--# Constants

local START_MARKER = "        # BEGIN GENERATED PR CHOICES"
local END_MARKER = "        # END GENERATED PR CHOICES"

--# Functions

function RefreshPRs.RenderChoices(source: string, raw: unknown): string
	local begin = source:find(START_MARKER, 1, true)
	local finish = source:find(END_MARKER, 1, true)
	assert(
		begin and finish and finish > begin and not source:find(START_MARKER, begin + 1, true),
		"PR dropdown markers missing or ambiguous"
	)
	local pulls: { PullRequest } = {}

	for _, value in Rules.Array(raw) do
		local pr = Rules.Entries(value)
		assert(type(pr.number) == "number" and type(pr.title) == "string", "Invalid PR display identity")

		if pr.state == nil or pr.state == "open" then
			table.insert(pulls, { number = pr.number, title = pr.title })
		end
	end

	table.sort(pulls, function(left: PullRequest, right: PullRequest)
		return left.number > right.number
	end)
	local lines = { source:sub(1, begin - 1) .. START_MARKER, "        options:", '          - "Source"' }

	for _, pr in pulls do
		table.insert(lines, "          - " .. Serde.encode("json", Request.PullRequestLabel(pr)))
	end

	return table.concat(lines, "\n") .. "\n" .. source:sub(finish)
end

function RefreshPRs.Run()
	if Process.env.ACT == "true" then
		return
	end

	local repo = GitHub.Repository()
	local pulls = {}
	local page = 1

	while true do
		local entries = Rules.Array(
			GitHub.Api("repos/" .. repo .. "/pulls?state=open&base=source&per_page=100&page=" .. tostring(page))
		)

		for _, entry in entries do
			table.insert(pulls, entry)
		end

		if #entries < 100 then
			break
		end

		page += 1
	end

	local file = ".github/workflows/ci.yml"
	local remote = table.find(Process.args, "--remote") ~= nil
	local original = if remote
		then Rules.Entries(GitHub.Api("repos/" .. repo .. "/contents/" .. file .. "?ref=source"))
		else nil
	local before: string

	if original then
		assert(type(original.content) == "string", "missing workflow content")
		before = Base64.Decode(original.content)
	else
		before = Fs.readFile(file)
	end

	local after = RefreshPRs.RenderChoices(before, pulls)

	if before == after then
		return
	end

	if original then
		GitHub.Api("repos/" .. repo .. "/contents/" .. file, "PUT", {
			branch = "source",
			sha = original.sha,
			message = "Refresh CI pull request choices [skip ci]",
			content = Base64.Encode(after),
		})
	else
		Fs.writeFile(file, after)
	end
end

return RefreshPRs
