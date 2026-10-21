-- ci/integration/publication.luau
--!strict

local Publication = {}

--# Modules

local Process = require("@lune/process")
local Request = require("./request")
local GitHub = require("../libraries/bootstrap/github")

--# Functions

function Publication.Authorize(env: Request.Environment?, administrator: ((string?) -> boolean)?): boolean
	local selected = env or Process.env
	assert(
		selected.ACT ~= "true"
			and selected.GITHUB_ACTIONS == "true"
			and selected.GITHUB_SERVER_URL == "https://github.com"
			and selected.GITHUB_REF == "refs/heads/source",
		"Local or untrusted publication denied; hosted source execution is required"
	)

	local isAdmin = administrator or GitHub.IsAdmin
	if selected.GITHUB_EVENT_NAME == "push" then
		assert(
			isAdmin(selected.GITHUB_ACTOR or GitHub.Actor()),
			"source publication requires an authorized administrator push"
		)
		return true
	end

	local controls = Request.Read(selected)
	assert(
		selected.GITHUB_EVENT_NAME == "workflow_dispatch"
			and Request.ParsePR(controls.pull_request) == 0
			and (controls.operation == "Publish" or controls.operation == "Full Run")
			and isAdmin(selected.GITHUB_ACTOR or GitHub.Actor()),
		"Manual publication requires a repository administrator and Publish or Full Run on Source"
	)

	return true
end

function Publication.Run()
	Publication.Authorize()
end

return Publication
