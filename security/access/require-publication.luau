-- security/access/require-publication.luau
--!strict

local RequirePublication = {}

--# Modules

local Process = require("@lune/process")
local Context = require("./context")
local Policy = require("./policy")
local Rules = require("../../libraries/registry/rules")

--# Functions

function RequirePublication.Run()
	assert(Policy.CanPublish(Context.Read(Process.env)), "publication context is not eligible")
	Rules.Validate(Process.env, Rules.Read("security/access/ruleset.json", "operation.rules"))
	local protection = Process.exec("node", {
		"publication/releases/cli.mjs",
		"protect",
		assert(Process.env.GITHUB_REPOSITORY),
	}, { stdio = "inherit" })
	assert(protection.ok, "repository source protection is required for publication")
end

return RequirePublication
