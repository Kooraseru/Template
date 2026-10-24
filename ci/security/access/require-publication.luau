-- ci/security/access/require-publication.luau
--!strict

local RequirePublication = {}

--# Modules

local Process = require("@lune/process")
local Context = require("./context")
local Policy = require("./policy")
local Rules = require("../../validation/rules")
local Protection = require("../../publication/releases/protection")

--# Functions

function RequirePublication.Run()
	assert(Policy.CanPublish(Context.Read(Process.env)), "publication context is not eligible")
	Rules.Validate(Process.env, Rules.Read("ci/security/access/ruleset.json", "operation.rules"))
	Protection.Require(assert(Process.env.GITHUB_REPOSITORY))
end

return RequirePublication
