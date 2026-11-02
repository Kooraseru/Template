-- repo/ci/components/projects/sync/init.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Publication = require("@ci/github/publication")
local Configuration = require("@ci/github/configuration")
local Catalog = require("@ci/github/projects/projectCatalog")
local Client = require("@ci/github/projects/projectClient")
local ProjectAuthentication = require("@ci/github/authentication/projectAuthentication")
local Authentication = require("@ci/github/authentication/authentication")
local ProjectSync = require("@self/projectSync")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	local supplied = ProjectAuthentication.Read()
	local projects = Catalog.Read()
	local repository = Publication.Begin("PROJECTS")
	if not repository then
		return "skipped"
	end
	local owners: { [string]: boolean } = {}
	for _, project in projects do
		owners[project.owner] = true
	end
	local configuration = Configuration.new()
	local defaultOwner = configuration:ResolveRepository(configuration.repository):match("^([^/]+)/")
	if defaultOwner then
		owners[defaultOwner] = true
	end
	local receipts: { ProjectSync.Receipt } = {}
	local skipped = false
	local changed = false
	local orderedOwners: { string } = {}
	for owner in owners do
		table.insert(orderedOwners, owner)
	end
	table.sort(orderedOwners)
	for _, owner in orderedOwners do
		local access = ProjectAuthentication.Acquire(supplied, repository, owner)
		if not access then
			skipped = true
			continue
		end
		local client = Client.new(access.token)
		local ok, result, modified = pcall(ProjectSync.Owner, repository, owner, projects, function(query, variables)
			return client:Query(query, variables)
		end)
		Authentication.Release(access)
		if not ok then
			local problem = tostring(result)
			if problem:find("PROJECT_AUTH:", 1, true) then
				local name = configuration.credentials.projects_token or "<github.credentials.projects_token>"
				print(
					`::warning::Projects sync skipped for {owner}: verify Projects access for the configured App or secret {name}. See the run summary for personal and organization setup instructions. Partial earlier operations may have succeeded.`
				)
				ProjectAuthentication.Warn(owner, "insufficient", access.inspection)
				skipped = true
				continue
			end
			error(problem, 0)
		end
		for _, receipt in result do
			table.insert(receipts, receipt)
		end
		if modified then
			changed = true
		end
	end
	Fs.writeDir("build/github/project-sync")
	Fs.writeFile(
		"build/github/project-sync/index.json",
		Serde.encode("json", { applied = not skipped, projects = receipts })
	)
	if skipped then
		return "skipped"
	end
	if not changed then
		print("GitHub Projects are already up to date; reconciliation completed successfully")
	end
	return nil
end

return Component
