-- .github/integration/source-approval.luau
--!strict

local SourceApproval = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Request = require("./request")
local GitHub = require("../../libraries/bootstrap/github")
local Rules = require("../../libraries/registry/rules")

--# Types

export type Approval = { kind: string, actor: string, source_sha: string, merged_by: string?, pr: number? }
export type Client = { Api: (string) -> unknown, IsAdmin: (string?) -> boolean }

--# Helpers

local function repository(raw: unknown): string?
	if type(raw) ~= "table" then
		return nil
	end

	local name = Rules.Entries(raw).full_name

	return if type(name) == "string" then name:lower() else nil
end

local function sourceBase(raw: unknown, name: string): boolean
	if type(raw) ~= "table" then
		return false
	end

	local base = Rules.Entries(raw)

	return base.ref == "source" and repository(base.repo) == name:lower()
end

--# Functions

function SourceApproval.Read(env: Request.Environment?, client: Client?): Approval?
	local selected = env or Process.env

	if
		selected.ACT == "true"
		or selected.GITHUB_ACTIONS ~= "true"
		or selected.GITHUB_SERVER_URL ~= "https://github.com"
		or selected.GITHUB_EVENT_NAME ~= "push"
		or selected.GITHUB_REF ~= "refs/heads/source"
	then
		return nil
	end

	local sha = selected.GITHUB_SHA
	local repo = selected.GITHUB_REPOSITORY
	local actor = selected.GITHUB_ACTOR

	if
		not sha
		or #sha ~= 40
		or not sha:match("^[a-f0-9]+$")
		or not repo
		or not repo:match("^[^/%s]+/[^/%s]+$")
		or not actor
	then
		return nil
	end

	if selected.GITHUB_EVENT_PATH and selected.GITHUB_EVENT_PATH ~= "" then
		local event = Rules.Entries(Serde.decode("json", Fs.readFile(selected.GITHUB_EVENT_PATH)))

		if
			event.deleted
			or event.after ~= sha
			or event.ref ~= selected.GITHUB_REF
			or repository(event.repository) ~= repo:lower()
		then
			return nil
		end
	end

	local api = if client then client.Api else GitHub.Api
	local isAdmin = if client then client.IsAdmin else GitHub.IsAdmin

	if not isAdmin(actor) then
		return nil
	end

	local page = 1

	while true do
		local pulls =
			Rules.Array(api("repos/" .. repo .. "/commits/" .. sha .. "/pulls?per_page=100&page=" .. tostring(page)))

		for _, raw in pulls do
			local candidate = Rules.Entries(raw)

			if candidate.merge_commit_sha == sha and candidate.merged_at and sourceBase(candidate.base, repo) then
				assert(
					type(candidate.number) == "number" and candidate.number > 0 and candidate.number % 1 == 0,
					"invalid PR identity"
				)
				local pr = Rules.Entries(api("repos/" .. repo .. "/pulls/" .. tostring(candidate.number)))
				local mergedBy = Rules.Entries(pr.merged_by or {}).login

				if
					pr.merged
					and pr.merge_commit_sha == sha
					and sourceBase(pr.base, repo)
					and type(mergedBy) == "string"
					and isAdmin(mergedBy)
				then
					assert(type(pr.number) == "number", "missing merged PR number")

					return {
						kind = "admin-merge",
						actor = actor,
						merged_by = mergedBy,
						pr = pr.number,
						source_sha = sha,
					}
				end
			end
		end

		if #pulls < 100 then
			break
		end

		page += 1
	end

	return { kind = "admin-source-push", actor = actor, source_sha = sha }
end

return SourceApproval
