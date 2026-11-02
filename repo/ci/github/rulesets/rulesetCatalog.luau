-- repo/ci/github/rulesets/rulesetCatalog.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Glob = require("@ci/bootstrap/discovery/glob")
local Publication = require("@ci/github/publication")

const ROOT = "repo/config/rulesets"

local RulesetCatalog = {}
export type Ruleset = { identity: string, definition: { [string]: unknown } }

local function known(record: { [string]: unknown }, allowed: { [string]: boolean }, path: string): ()
	for name in record do
		if not allowed[name] then
			error(`{path}: unknown configuration field {name}`, 0)
		end
	end
end

local function strings(value: unknown, path: string): { string }
	if type(value) ~= "table" then
		error(`{path}: expected an array of refs`, 0)
	end
	local result: { string } = {}
	for index, item in value do
		if type(index) ~= "number" or type(item) ~= "string" or item == "" then
			error(`{path}: expected an array of nonempty strings`, 0)
		end
		table.insert(result, item)
	end
	return result
end

local function entries(value: unknown, path: string): { { [string]: unknown } }
	if type(value) ~= "table" then
		error(`{path}: expected an array`, 0)
	end
	local result: { { [string]: unknown } } = {}
	for index, item in value do
		if type(index) ~= "number" then
			error(`{path}: expected an array`, 0)
		end
		table.insert(result, Publication.Record(item))
	end
	return result
end

function RulesetCatalog.Read(): { Ruleset }
	local result: { Ruleset } = {}
	local identities: { [string]: boolean } = {}
	local names: { [string]: boolean } = {}
	for _, path in Glob.Find(`{ROOT}/*.toml`) do
		local identity = path:match("/([%w_-]+)%.toml$")
		if not identity or not Fs.isFile(path) then
			error(`{path}: expected a ruleset TOML file`, 0)
		end
		if identities[identity:lower()] then
			error(`{path}: duplicate ruleset identity`, 0)
		end
		identities[identity:lower()] = true
		local root = Publication.Record(Serde.decode("toml", Fs.readFile(path)))
		known(root, { ruleset = true, bypass_actors = true, rules = true }, path)
		local definition = Publication.Record(root.ruleset)
		known(definition, { name = true, target = true, enforcement = true, include = true, exclude = true }, path)
		local name = Publication.Text(definition.name)
		if names[name:lower()] then
			error(`{path}: duplicate ruleset display name {name}`, 0)
		end
		names[name:lower()] = true
		local target = Publication.Text(definition.target)
		local enforcement = Publication.Text(definition.enforcement)
		if target ~= "branch" and target ~= "tag" then
			error(`{path}: target must be branch or tag`, 0)
		end
		if enforcement ~= "active" and enforcement ~= "disabled" then
			error(`{path}: enforcement must be active or disabled`, 0)
		end
		local include = strings(definition.include, path)
		local exclude = strings(definition.exclude, path)
		if #include == 0 then
			error(`{path}: include must select at least one ref`, 0)
		end
		local rules = entries(root.rules, path)
		if #rules == 0 then
			error(`{path}: expected at least one [[rules]] definition`, 0)
		end
		local ruleNames: { [string]: boolean } = {}
		for _, rule in rules do
			known(rule, { type = true, parameters = true }, path)
			local ruleType = Publication.Text(rule.type)
			if not ruleType:match("^[a-z_]+$") or ruleNames[ruleType] then
				error(`{path}: invalid or duplicate rule type {ruleType}`, 0)
			end
			ruleNames[ruleType] = true
			if rule.parameters ~= nil then
				Publication.Record(rule.parameters)
			end
		end
		local bypass = entries(root.bypass_actors or {}, path)
		for _, actor in bypass do
			known(actor, { actor_id = true, actor_type = true, bypass_mode = true }, path)
			local actorType = Publication.Text(actor.actor_type)
			local mode = Publication.Text(actor.bypass_mode)
			if actorType ~= "RepositoryRole" and actorType ~= "Integration" and actorType ~= "User" and actorType ~= "Team" then
				error(`{path}: unsupported bypass actor type {actorType}`, 0)
			end
			if type(actor.actor_id) ~= "number" or actor.actor_id < 0 or actor.actor_id % 1 ~= 0 then
				error(`{path}: bypass actor requires an integer actor_id`, 0)
			end
			if mode ~= "always" and mode ~= "pull_request" then
				error(`{path}: bypass_mode must be always or pull_request`, 0)
			end
		end
		table.insert(result, {
			identity = identity,
			definition = {
				name = name,
				target = target,
				enforcement = enforcement,
				conditions = { ref_name = { include = include, exclude = exclude } },
				bypass_actors = bypass,
				rules = rules,
			},
		})
	end
	return result
end

return RulesetCatalog
