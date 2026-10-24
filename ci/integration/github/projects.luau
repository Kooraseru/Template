-- ci/integration/github/projects.luau
--!strict

local Projects = {}

--# Modules

local Stdio = require("@lune/stdio")

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Client = require("./client")
local Definitions = require("./definitions")

--# Helpers

local function emit(message: string)
	Stdio.write(message .. "\n")
end

local function mutate(name: string, inputType: string, input: { [string]: unknown }): Client.Record
	local query = "mutation($input:" .. inputType .. "!){ " .. name .. "(input:$input){ projectV2{id} } }"
	return Client.Object(Client.Graphql(query, { input = input })[name])
end

local function graphql(query: string, values: { [string]: unknown }): Client.Record
	return Client.Graphql(query, values)
end

local function repository(): (string, Client.Record, Client.Record)
	local owner, name = Client.Repository()
	local data = graphql(
		[[query($owner:String!,$name:String!){
      repository(owner:$owner,name:$name){
        id isPrivate
        owner { __typename id
          ... on User { projectsV2(first:100){
            nodes{id title public shortDescription url} pageInfo{hasNextPage}
          }}
          ... on Organization { projectsV2(first:100){
            nodes{id title public shortDescription url} pageInfo{hasNextPage}
          }}
        }
      }
    }]],
		{ owner = owner, name = name }
	)
	local repo = Client.Object(data.repository)
	return owner, repo, Client.Object(repo.owner)
end

local function projectsUnder(owner: Client.Record): { [string]: Client.Record }
	local connection = Client.Object(owner.projectsV2)
	local page = Client.Object(connection.pageInfo)
	assert(page.hasNextPage == false, "project list pagination unsupported; refusing incomplete reconciliation")
	local projects: { [string]: Client.Record } = {}
	for _, value in Client.Array(connection.nodes) do
		local entry = Client.Object(value)
		local title = assert(entry.title, "project missing title")
		assert(type(title) == "string", "invalid remote project title")
		assert(projects[title] == nil, "ambiguous project title: " .. title)
		projects[title] = entry
	end
	return projects
end

local function projectDetails(id: string): Client.Record
	local query = [[query($id:ID!){node(id:$id){... on ProjectV2{
      fields(first:100){pageInfo{hasNextPage} nodes{
        __typename ... on ProjectV2Field{name dataType}
        ... on ProjectV2SingleSelectField{name options{name}}
      }}
      views(first:100){pageInfo{hasNextPage} nodes{name layout}}
      repositories(first:100){pageInfo{hasNextPage} nodes{id}}
    }}}]]
	return Client.Object(graphql(query, { id = id }).node)
end

local function createProject(owner: Client.Record, repo: Client.Record, wanted: Definitions.Project): string
	-- Create private, then set visibility explicitly before adding content.
	local mutation = [[mutation($input:CreateProjectV2Input!){
      createProjectV2(input:$input){projectV2{id}}
    }]]
	local created = Client.Object(graphql(mutation, {
		input = { ownerId = owner.id, repositoryId = repo.id, title = wanted.title },
	}).createProjectV2)
	local id = assert(Client.Object(created.projectV2).id, "created project missing ID")
	assert(type(id) == "string", "invalid project ID")
	mutate("updateProjectV2", "UpdateProjectV2Input", {
		projectId = id,
		public = wanted.visibility == "public",
		shortDescription = wanted.description,
	})
	return id
end

local function createField(projectId: string, field: Definitions.Field)
	local input: { [string]: unknown } = {
		projectId = projectId,
		name = field.name,
		dataType = string.upper(field.dataType),
	}
	if field.dataType == "single_select" then
		local options = {}
		for _, name in field.options do
			table.insert(options, { name = name, description = "", color = "GRAY" })
		end
		input.singleSelectOptions = options
	end
	local query = [[mutation($input:CreateProjectV2FieldInput!){
      createProjectV2Field(input:$input){projectV2Field{... on ProjectV2Field{id}
      ... on ProjectV2SingleSelectField{id}}}
    }]]
	graphql(query, { input = input })
end

local function createView(projectId: string, view: Definitions.View)
	local query = [[mutation($input:CreateProjectV2ViewInput!){
      createProjectV2View(input:$input){projectV2View{id}}
    }]]
	graphql(query, {
		input = {
			projectId = projectId,
			name = view.name,
			layout = string.upper(view.layout) .. "_LAYOUT",
		},
	})
end

local function reconcile(
	wanted: Definitions.Project,
	existing: Client.Record?,
	owner: Client.Record,
	repo: Client.Record,
	apply: boolean
): number
	local changes = 0
	local id: string
	local fresh = existing == nil
	if not existing then
		emit("CREATE project " .. wanted.title .. " (" .. wanted.visibility .. ")")
		changes += 1
		if not apply then
			-- Still describe fields and views when the project is missing.
			for _, field in wanted.fields do
				emit("  CREATE field " .. field.name)
			end
			for _, view in wanted.views do
				emit("  CREATE view " .. view.name)
			end
			return changes + #wanted.fields + #wanted.views
		end
		id = createProject(owner, repo, wanted)
	else
		id = assert(existing.id, "project ID missing") :: string
		-- An unexpected visibility change can expose private data: do not auto-update it.
		assert(
			existing.public == (wanted.visibility == "public"),
			"project " .. wanted.title .. " visibility drift; manual review required"
		)
		assert(
			existing.shortDescription == wanted.description,
			"project " .. wanted.title .. " description drift; manual review required"
		)
	end

	local details = if fresh then nil else projectDetails(id)
	local fields: { [string]: Client.Record } = {}
	local views: { [string]: Client.Record } = {}
	if details then
		local fc = Client.Object(details.fields)
		local vc = Client.Object(details.views)
		local connections: { Client.Record } = { fc, vc }
		for _, c in connections do
			assert(
				Client.Object(c.pageInfo).hasNextPage == false,
				"project contains too many fields or views to reconcile safely"
			)
		end
		for _, raw in Client.Array(fc.nodes) do
			local entry = Client.Object(raw)
			if type(entry.name) == "string" then
				assert(fields[entry.name] == nil, "duplicate project field")
				fields[entry.name] = entry
			end
		end
		for _, raw in Client.Array(vc.nodes) do
			local entry = Client.Object(raw)
			if type(entry.name) == "string" then
				assert(views[entry.name] == nil, "duplicate project view")
				views[entry.name] = entry
			end
		end
	end

	for _, field in wanted.fields do
		local current = fields[field.name]
		if current == nil then
			emit("  CREATE field " .. field.name)
			changes += 1
			if apply then
				createField(id, field)
			end
		else
			local expected = if field.dataType == "single_select"
				then "ProjectV2SingleSelectField"
				else "ProjectV2Field"
			assert(current.__typename == expected, "project field type drift: " .. field.name)
			if field.dataType == "single_select" then
				local actualOptions = Client.Array(current.options)
				assert(#actualOptions == #field.options, "field options drift: " .. field.name)
				for _, raw in actualOptions do
					local option = Client.Object(raw)
					assert(
						type(option.name) == "string" and table.find(field.options, option.name),
						"field options drift: " .. field.name
					)
				end
			else
				assert(current.dataType == string.upper(field.dataType), "project field type drift: " .. field.name)
			end
		end
	end
	for _, view in wanted.views do
		local current = views[view.name]
		if current == nil then
			emit("  CREATE view " .. view.name)
			changes += 1
			if apply then
				createView(id, view)
			end
		else
			assert(current.layout == string.upper(view.layout) .. "_LAYOUT", "project view layout drift: " .. view.name)
		end
	end
	if wanted.mode == "template" and owner.__typename == "Organization" and fresh then
		emit("  MARK native organization template " .. wanted.title)
		if apply then
			local query = [[mutation($input:MarkProjectV2AsTemplateInput!){
              markProjectV2AsTemplate(input:$input){projectV2{id}}
            }]]
			graphql(query, { input = { projectId = id } })
		end
	end
	-- Linking is established when creating projects. Existing projects may
	-- have been linked manually; never transfer ownership automatically.
	if not fresh then
		local repos = Client.Object(assert(details).repositories)
		assert(Client.Object(repos.pageInfo).hasNextPage == false, "project repository links are truncated")
		local linked = false
		for _, raw in Client.Array(repos.nodes) do
			if Client.Object(raw).id == repo.id then
				linked = true
			end
		end
		if not linked then
			emit("  LINK project " .. wanted.title .. " to repository")
			changes += 1
			if apply then
				local query = [[mutation($input:LinkProjectV2ToRepositoryInput!){
                  linkProjectV2ToRepository(input:$input){repository{id}}
                }]]
				graphql(query, { input = { projectId = id, repositoryId = repo.id } })
			end
		end
	end
	return changes
end

local function handleEvent(wanted: { Definitions.Project })
	local location = assert(Process.env.GITHUB_EVENT_PATH, "missing GitHub event path")
	local event: unknown = Serde.decode("json", Fs.readFile(location))
	local payload = Client.Object(event)
	local action = assert(payload.action, "missing event action")
	assert(type(action) == "string", "invalid event action")
	local issue = payload.issue
	local pr = payload.pull_request
	local source = if issue then Client.Object(issue) else Client.Object(pr)
	local nodeId = assert(source.node_id, "missing event content node ID")
	assert(type(nodeId) == "string", "invalid event content node ID")
	local eventName = if issue then "issues." .. action else "pull_request." .. action
	local labels: { string } = {}
	for _, raw in Client.Array(source.labels or {}) do
		local label = Client.Object(raw)
		if type(label.name) == "string" then
			table.insert(labels, label.name)
		end
	end
	local _, repo, owner = repository()
	local projects = projectsUnder(owner)
	for _, project in wanted do
		if project.mode ~= "managed" or (repo.isPrivate and project.visibility == "public") then
			continue
		end
		for _, automation in project.automations do
			if automation.event ~= eventName then
				continue
			end
			local matches = #automation.labels == 0
			for _, label in automation.labels do
				matches = matches or table.find(labels, label) ~= nil
			end
			if not matches then
				continue
			end
			local current = projects[project.title]
			assert(current ~= nil, "project missing for event automation: " .. project.title)
			local query = [[mutation($input:AddProjectV2ItemByIdInput!){
              addProjectV2ItemById(input:$input){item{id}}
            }]]
			graphql(query, { input = { projectId = current.id, contentId = nodeId } })
			emit("Added " .. eventName .. " to " .. project.title)
			break
		end
	end
end

--# Functions

function Projects.Run(operation: string)
	local definitions = Definitions.ReadProjects()
	if operation == "validate" then
		emit("Validated " .. #definitions .. " GitHub project definitions")
		return
	end
	if operation == "event" then
		handleEvent(definitions)
		return
	end
	local _, repo, owner = repository()
	local current = projectsUnder(owner)
	local changes = 0
	for _, definition in definitions do
		if repo.isPrivate and definition.visibility == "public" then
			-- A public project may be created, but must never receive private items.
			emit("NOTICE: public " .. definition.title .. " will not receive private repository items")
		end
		changes += reconcile(definition, current[definition.title], owner, repo, operation == "apply")
	end
	emit("Projects: " .. changes .. " proposed change(s)")
end

return Projects
