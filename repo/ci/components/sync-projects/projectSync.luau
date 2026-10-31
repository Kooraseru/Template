-- repo/ci/components/sync-projects/projectSync.luau
--!strict

local Publication = require("@ci/github/publication")
local Catalog = require("@ci/github/projectCatalog")
local Client = require("@ci/github/projectClient")

const OWNER_QUERY =
	[[query($login:String!,$after:String){repositoryOwner(login:$login){id ... on User{projectsV2(first:100,after:$after){nodes{id title readme shortDescription public closed url} pageInfo{hasNextPage endCursor}}} ... on Organization{projectsV2(first:100,after:$after){nodes{id title readme shortDescription public closed url} pageInfo{hasNextPage endCursor}}}}}]]
const FIELDS_QUERY =
	[[query($id:ID!,$after:String){node(id:$id){... on ProjectV2{fields(first:100,after:$after){nodes{... on ProjectV2FieldCommon{id name dataType isIssueField} ... on ProjectV2SingleSelectField{options{id name color description}}} pageInfo{hasNextPage endCursor}}}}}]]
const REPOSITORIES_QUERY =
	[[query($id:ID!,$after:String){node(id:$id){... on ProjectV2{repositories(first:100,after:$after){nodes{id} pageInfo{hasNextPage endCursor}}}}}]]
const CUSTOM_TYPES =
	{ TEXT = true, NUMBER = true, DATE = true, SINGLE_SELECT = true, MULTI_SELECT = true, ITERATION = true }

local ProjectSync = {}
export type Receipt = { identity: string, id: string, url: string }

local function array(value: unknown, label: string): { { [string]: unknown } }
	if type(value) ~= "table" then
		error(`Projects response: expected {label} array`, 0)
	end
	local result: { { [string]: unknown } } = {}
	for _, item in value do
		table.insert(result, Publication.Record(item))
	end
	return result
end

local function connection(
	query: Client.Query,
	document: string,
	variables: { [string]: unknown },
	select: ({ [string]: unknown }) -> { [string]: unknown }
): { { [string]: unknown } }
	local result: { { [string]: unknown } } = {}
	local cursor: unknown = nil
	repeat
		variables.after = cursor
		local data = select(query(document, variables))
		for _, node in array(data.nodes, "nodes") do
			table.insert(result, node)
		end
		local page = Publication.Record(data.pageInfo)
		if page.hasNextPage ~= true then
			break
		end
		local nextCursor = Publication.Text(page.endCursor)
		if nextCursor == cursor then
			error("Projects pagination did not advance", 0)
		end
		cursor = nextCursor
	until false
	return result
end

local function syncFields(projectId: string, desired: { Catalog.Field }, query: Client.Query): boolean
	local existing = connection(query, FIELDS_QUERY, { id = projectId }, function(data)
		return Publication.Record(Publication.Record(data.node).fields)
	end)
	local byName: { [string]: { [string]: unknown } } = {}
	for _, field in existing do
		local name = Publication.Text(field.name):lower()
		if byName[name] then
			error(`Ambiguous existing project field {name}`, 0)
		end
		byName[name] = field
	end
	local declared: { [string]: boolean } = {}
	local changed = false
	for _, field in desired do
		local key = field.name:lower()
		declared[key] = true
		local current = byName[key]
		if current and current.isIssueField == true then
			error(
				`Project field {field.name} is an organization issue field; it cannot be overwritten as a project field`,
				0
			)
		end
		if current and current.dataType ~= field.dataType then
			error(
				`Project field {field.name} has a different type; refusing to delete its existing item values to change type`,
				0
			)
		end
		local options: { { [string]: unknown } }? = nil
		local sameOptions = true
		if field.options then
			options = {}
			local oldOptions = if current then array(current.options, "field options") else {}
			local oldByName: { [string]: { [string]: unknown } } = {}
			for _, old in oldOptions do
				oldByName[Publication.Text(old.name):lower()] = old
			end
			if #oldOptions ~= #field.options then
				sameOptions = false
			end
			for index, option in field.options do
				local old = oldByName[option.name:lower()]
				local value: { [string]: unknown } =
					{ name = option.name, color = option.color, description = option.description }
				if old then
					value.id = Publication.Text(old.id)
				end
				table.insert(options, value)
				local prior = oldOptions[index]
				if
					not prior
					or prior.name ~= option.name
					or prior.color ~= option.color
					or prior.description ~= option.description
				then
					sameOptions = false
				end
			end
		end
		if not current then
			query(
				[[mutation($input:CreateProjectV2FieldInput!){createProjectV2Field(input:$input){projectV2Field{... on ProjectV2FieldCommon{id}}}}]],
				{
					input = {
						projectId = projectId,
						name = field.name,
						dataType = field.dataType,
						singleSelectOptions = options,
					},
				}
			)
			changed = true
		elseif current.name ~= field.name or not sameOptions then
			query(
				[[mutation($input:UpdateProjectV2FieldInput!){updateProjectV2Field(input:$input){projectV2Field{... on ProjectV2FieldCommon{id}}}}]],
				{
					input = { fieldId = Publication.Text(current.id), name = field.name, singleSelectOptions = options },
				}
			)
			changed = true
		end
	end
	for _, field in existing do
		local name = Publication.Text(field.name)
		local dataType = Publication.Text(field.dataType)
		-- GitHub system and organization issue fields are not owned by this project blueprint.
		if declared[name:lower()] or not CUSTOM_TYPES[dataType] or field.isIssueField == true or name == "Status" then
			continue
		end
		query(
			[[mutation($input:DeleteProjectV2FieldInput!){deleteProjectV2Field(input:$input){clientMutationId}}]],
			{ input = { fieldId = Publication.Text(field.id) } }
		)
		changed = true
	end
	return changed
end

function ProjectSync.Owner(
	repository: string,
	owner: string,
	projects: { Catalog.Project },
	query: Client.Query
): ({ Receipt }, boolean)
	local ownerId: string? = nil
	local existing = connection(query, OWNER_QUERY, { login = owner }, function(data)
		local account = Publication.Record(data.repositoryOwner)
		ownerId = Publication.Text(account.id)
		return Publication.Record(account.projectsV2)
	end)
	if not ownerId then
		error(`Project owner {owner} could not be resolved`, 0)
	end
	local repositoryOwner, repositoryName = repository:match("^([^/]+)/([^/]+)$")
	if not repositoryOwner or not repositoryName then
		error("Invalid Projects repository path", 0)
	end
	local repoData = query(
		[[query($owner:String!,$name:String!){repository(owner:$owner,name:$name){id}}]],
		{ owner = repositoryOwner, name = repositoryName }
	)
	local repositoryId = Publication.Text(Publication.Record(repoData.repository).id)
	local desiredKeys: { [string]: boolean } = {}
	local receipts: { Receipt } = {}
	local changed = false
	for _, project in projects do
		if project.owner ~= owner then
			continue
		end
		local marker = `<!-- repository-project:{project.managementKey} -->`
		desiredKeys[marker] = true
		local current: { [string]: unknown }? = nil
		for _, candidate in existing do
			if type(candidate.readme) == "string" and candidate.readme:find(marker, 1, true) then
				if current then
					error(`Multiple projects claim management identity {project.managementKey}`, 0)
				end
				current = candidate
			end
		end
		if not current then
			local created =
				query([[mutation($input:CreateProjectV2Input!){createProjectV2(input:$input){projectV2{id url}}}]], {
					input = { ownerId = ownerId, title = project.title, repositoryId = repositoryId },
				})
			current = Publication.Record(Publication.Record(created.createProjectV2).projectV2)
			changed = true
		end
		if not current then
			error("Projects API did not return the created project", 0)
		end
		local id = Publication.Text(current.id)
		local readme = project.readme .. "\n\n" .. marker
		if
			current.title ~= project.title
			or current.readme ~= readme
			or current.shortDescription ~= project.description
			or current.public ~= project.public
			or current.closed ~= false
		then
			query([[mutation($input:UpdateProjectV2Input!){updateProjectV2(input:$input){projectV2{id}}}]], {
				input = {
					projectId = id,
					title = project.title,
					readme = readme,
					shortDescription = project.description,
					public = project.public,
					closed = false,
				},
			})
			changed = true
		end
		local repositories = connection(query, REPOSITORIES_QUERY, { id = id }, function(data)
			return Publication.Record(Publication.Record(data.node).repositories)
		end)
		local linked = false
		for _, linkedRepository in repositories do
			if linkedRepository.id == repositoryId then
				linked = true
			end
		end
		if not linked then
			query(
				[[mutation($input:LinkProjectV2ToRepositoryInput!){linkProjectV2ToRepository(input:$input){clientMutationId}}]],
				{ input = { projectId = id, repositoryId = repositoryId } }
			)
			changed = true
		end
		if syncFields(id, project.fields, query) then
			changed = true
		end
		table.insert(receipts, { identity = project.identity, id = id, url = Publication.Text(current.url) })
		print(`Reconciled GitHub Project {project.identity}: {Publication.Text(current.url)}`)
	end
	local prefix = `<!-- repository-project:{repository}:`
	for _, project in existing do
		if type(project.readme) ~= "string" or project.closed == true then
			continue
		end
		local start = project.readme:find(prefix, 1, true)
		if not start then
			continue
		end
		local finish = project.readme:find(" -->", start, true)
		if not finish then
			continue
		end
		local marker = project.readme:sub(start, finish + 3)
		if desiredKeys[marker] then
			continue
		end
		query(
			[[mutation($input:UpdateProjectV2Input!){updateProjectV2(input:$input){projectV2{id}}}]],
			{ input = { projectId = Publication.Text(project.id), closed = true } }
		)
		print(`Closed undeclared managed Project {Publication.Text(project.id)}; its items were retained`)
		changed = true
	end
	return receipts, changed
end

return ProjectSync
