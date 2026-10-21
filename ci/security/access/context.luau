-- ci/security/access/context.luau
--!strict

local Context = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Policy = require("./policy")
local Rules = require("../../libraries/registry/rules")
local Publication = require("../../integration/publication")

--# Functions

function Context.Repository(event: unknown): string?

	if type(event) ~= "table" then
		return nil
	end

	local repository = Rules.Entries(event).repository

	if type(repository) ~= "table" then
		return nil
	end

	local name = Rules.Entries(repository).full_name

	return if type(name) == "string" and name ~= "" then name else nil
end

function Context.Read(env: { [string]: string? }): Policy.Context
	local repository: string? = nil

	if env.GITHUB_EVENT_PATH then
		local event = Serde.decode("json", Fs.readFile(env.GITHUB_EVENT_PATH))
		repository = Context.Repository(event)
	end

	local allowed = false

	if env.GITHUB_EVENT_NAME == "workflow_dispatch" or env.GITHUB_EVENT_NAME == "push" then
		allowed = pcall(function()
			Publication.Authorize(env)
		end)
	end

	return {
		manualAllowed = env.GITHUB_EVENT_NAME == "workflow_dispatch" and allowed,
		pushAllowed = env.GITHUB_EVENT_NAME == "push" and allowed,
		localRun = env.ACT == "true",
		actions = env.GITHUB_ACTIONS,
		server = env.GITHUB_SERVER_URL,
		event = env.GITHUB_EVENT_NAME,
		ref = env.GITHUB_REF,
		repository = env.GITHUB_REPOSITORY,
		eventRepository = repository,
	}
end

return Context
