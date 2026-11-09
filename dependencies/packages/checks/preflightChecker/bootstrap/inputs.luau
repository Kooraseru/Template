-- dependencies/packages/checks/preflightChecker/bootstrap/inputs.luau
--!strict

local Configuration = require("@ci/github/configuration")
local Glob = require("@ci/bootstrap/discovery/glob")
local Json = require("@formats/json")
local LabelCatalog = require("@ci/components/work/labels/sync/labelCatalog")

local configuration = Configuration.new()
local branches: { string } = {}
for _, path in Glob.Find(".github/config/branches/*.toml") do
	local name = path:match("/([%w][%w_-]*)%.toml$")
	if not name then
		error("Invalid configured publication branch", 0)
	end
	table.insert(branches, name)
end
print(Json.encode({
	repository = configuration:ResolveRepository(configuration.repository),
	labels = LabelCatalog.Read(),
	branches = branches,
}))
