-- repo/ci/github/responses.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Glob = require("@ci/bootstrap/glob")
local Contract = require("@ci/bootstrap/contract")
local Configuration = require("./configuration")
local Publication = require("./publication")

const ROOT = "repo/config/ci/responses"
const RECORDS = "build/github/responses"

local Responses = {}
local written = false
export type Record = { id: string, markdown: string, component: string, color: string }
type Entry = { id: string, markdown: string, components: { [string]: boolean }, color: string, index: number }
type Branch = { name: string, children: { [string]: Branch }, outcome: string?, component: string }

local function configuration(): { [string]: unknown }
	local config = Publication.Record(Serde.decode("toml", Fs.readFile(`{ROOT}/responses.toml`)))
	if config.version ~= 1 then
		error("responses.toml: version must be 1", 0)
	end
	return config
end

local function read(path: string): string
	if not path:match("^[%w_./-]+%.md$") or path:sub(1, 1) == "/" then
		error("Invalid response Markdown path", 0)
	end
	for segment in path:gmatch("[^/]+") do
		if segment == "." or segment == ".." then
			error("Response paths must stay within the response directory", 0)
		end
	end
	return Fs.readFile(`{ROOT}/{path}`)
end

function Responses.Template(role: string): string
	local templates = Publication.Record(configuration().templates)
	return read(Publication.Text(templates[role]))
end

function Responses.Fill(markdown: string, values: { [string]: string }): string
	local result = markdown:gsub("{{([%w_]+)}}", function(key)
		return values[key] or error(`Response value is missing: {key}`, 0)
	end)
	return result
end

local function color(name: string): (string, string)
	local aliases = Publication.Record(configuration().colors)
	local seen: { [string]: boolean } = {}
	while not name:match("^github%.") do
		if seen[name] then
			error("Response color alias cycle", 0)
		end
		seen[name] = true
		name = Publication.Text(aliases[name])
	end
	local styles = {
		["github.note"] = { "", "NOTE" },
		["github.tip"] = { "", "TIP" },
		["github.important"] = { "", "IMPORTANT" },
		["github.warning"] = { "", "WARNING" },
		["github.caution"] = { "", "CAUTION" },
	}
	local style = styles[name]
	if not style then
		error(`Unsupported GitHub response color: {name}`, 0)
	end
	return style[1], style[2]
end

local function htmlAttribute(value: string): string
	return (value:gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function shieldcnButton(name: string, values: { [string]: string }, config: { [string]: unknown }): string
	local buttons = Publication.Record(config.buttons)
	local defaults = Publication.Record(buttons.defaults)
	local button = Publication.Record(buttons[name])
	local destination = Publication.Text(button.target)
	local href = values[destination]
	if not href or href == "" then
		return ""
	end

	local label = Publication.Text(button.label)
	local logo = Publication.Text(button.logo)
	if not logo:match("^[%w:_%-]+$") then
		error(`Invalid Shieldcn logo for button {name}`, 0)
	end
	local size = Publication.Text(button.size or defaults.size)
	if size ~= "xs" and size ~= "sm" and size ~= "default" and size ~= "lg" then
		error(`Invalid Shieldcn size for button {name}`, 0)
	end
	local variant = Publication.Text(button.variant or defaults.variant)
	local logoColor = Publication.Text(button.logo_color or defaults.logo_color)
	if not logoColor:match("^%x%x%x(%x%x%x)?$") then
		error(`Invalid Shieldcn logo color for button {name}`, 0)
	end

	local rawGradients = config.gradients
	if type(rawGradients) ~= "table" then
		error("responses.toml: gradients must be a table", 0)
	end
	local gradients = rawGradients :: { [string]: unknown }
	local rawPalette = gradients[Publication.Text(button.gradient)]
	if type(rawPalette) ~= "table" then
		error(`Shieldcn gradient for button {name} must contain two colors`, 0)
	end
	local palette = rawPalette :: { unknown }
	if #palette ~= 2 then
		error(`Shieldcn gradient for button {name} must contain two colors`, 0)
	end
	local first = Publication.Text(palette[1])
	local second = Publication.Text(palette[2])
	if not first:match("^%x%x%x%x%x%x$") or not second:match("^%x%x%x%x%x%x$") then
		error(`Invalid Shieldcn gradient for button {name}`, 0)
	end

	local slug = label:gsub("_", "__"):gsub("%-", "--"):gsub("%s+", "_")
	local image =
		`https://shieldcn.dev/badge/{Publication.Encode(slug)}.svg?gradient={first}%2C{second}&size={Publication.Encode(
			size
		)}&logo={Publication.Encode(logo)}&logoColor={Publication.Encode(logoColor)}&variant={Publication.Encode(
			variant
		)}`
	image = image:gsub("&", "&amp;")
	return `<a href="{htmlAttribute(href)}"><img alt="{htmlAttribute(label)}" src="{image}"></a>`
end

function Responses.Prepare(): string
	local component = Process.env.CI_COMPONENT or "bootstrap"
	if not Contract.ValidIdentity(component) then
		error("Invalid response component identity", 0)
	end
	local directory = `{RECORDS}/{Contract.Key(component)}`
	Fs.writeDir(`{directory}/records`)
	Fs.writeFile(`{directory}/metadata.json`, Serde.encode("json", { component = component }))
	return directory
end

function Responses.Record(id: string, markdown: string, selectedColor: string?): ()
	if not Contract.ValidIdentity(id) then
		error("Invalid response record identity", 0)
	end
	local directory = Responses.Prepare()
	local record: Record = {
		id = id,
		markdown = markdown,
		component = Process.env.CI_COMPONENT or "bootstrap",
		color = selectedColor or "warning",
	}
	color(record.color)
	Fs.writeFile(`{directory}/records/{Contract.Key(id)}.json`, Serde.encode("json", record))
end

local function records(): { Record }
	local result: { Record } = {}
	for _, path in Glob.Find(`{RECORDS}/*/records/*.json`) do
		local raw = Publication.Record(Serde.decode("json", Fs.readFile(path)))
		local record: Record = {
			id = Publication.Text(raw.id),
			markdown = Publication.Text(raw.markdown),
			component = Publication.Text(raw.component),
			color = Publication.Text(raw.color),
		}
		if not Contract.ValidIdentity(record.id) or not Contract.ValidIdentity(record.component) then
			error(`{path}: invalid response record`, 0)
		end
		table.insert(result, record)
	end
	return result
end

local function combine(source: { Record }): { Entry }
	table.sort(source, function(a: Record, b: Record): boolean
		return a.id .. a.component < b.id .. b.component
	end)
	local result: { Entry } = {}
	local known: { [string]: Entry } = {}
	for _, record in source do
		local key = record.id .. "\0" .. record.markdown .. "\0" .. record.color
		local entry = known[key]
		if not entry then
			entry = {
				id = record.id,
				markdown = record.markdown,
				color = record.color,
				components = {},
				index = #result + 1,
			}
			known[key] = entry
			table.insert(result, entry)
		end
		entry.components[record.component] = true
	end
	return result
end

local function keys<T>(map: { [string]: T }): { string }
	local names: { string } = {}
	for name in map do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function outcomeColor(outcome: string): string
	if outcome:find("fail", 1, true) then
		return "failure"
	end
	if outcome == "passed" or outcome == "success" then
		return "success"
	end
	if outcome == "blocked" or outcome == "timed_out" then
		return "warning"
	end
	return "neutral"
end

local function componentTree(outcomes: { [string]: string }, entries: { Entry }): string
	local tree: Branch = { name = "", children = {}, component = "" }
	for identity, outcome in outcomes do
		local node = tree
		for segment in identity:gmatch("[^/]+") do
			if not node.children[segment] then
				node.children[segment] = { name = segment, children = {}, component = "" }
			end
			node = node.children[segment]
		end
		node.outcome = outcome
		node.component = identity
	end
	local function needsAttention(node: Branch): boolean
		if node.outcome then
			return node.outcome ~= "passed" and node.outcome ~= "success"
		end
		for _, child in node.children do
			if needsAttention(child) then
				return true
			end
		end
		return false
	end
	local function render(node: Branch): string
		if node.outcome then
			local links: { string } = {}
			for _, entry in entries do
				if entry.components[node.component] then
					table.insert(links, `[details {entry.index}](#response-{entry.index})`)
				end
			end
			local marker = color(outcomeColor(node.outcome))
			local markdown = Responses.Fill(Responses.Template("components.component"), {
				name = node.name,
				outcome = node.outcome,
				status_marker = marker,
				details_links = table.concat(links, ", "),
			})
			return (markdown:gsub("\n+$", ""))
		end
		local children: { string } = {}
		local rows: { string } = {}
		for _, name in keys(node.children) do
			local child = node.children[name]
			table.insert(if child.outcome then rows else children, render(child))
		end
		local text = table.concat(children, "\n\n")
		local tableText = if #rows > 0
			then "| Component | Outcome | Details |\n| --- | --- | --- |\n" .. table.concat(rows, "\n")
			else ""
		if node.name == "" then
			return tableText .. (if tableText ~= "" and text ~= "" then "\n\n" else "") .. text
		end
		local expanded = if needsAttention(node) then " open" else ""
		local markdown = Responses.Fill(Responses.Template("components.group"), {
			name = node.name,
			rows = tableText,
			children = text,
			expanded = expanded,
		})
		return (markdown:gsub("\n+$", ""))
	end
	return render(tree)
end

function Responses.Render(
	root: string,
	values: { [string]: string },
	outcomes: { [string]: string }?,
	source: { Record }?
): string
	local config = configuration()
	local entries = combine(source or records())
	local context = table.clone(values)
	local repository = Process.env.GITHUB_REPOSITORY or Configuration.new().repository
	local base = (Process.env.GITHUB_SERVER_URL or "https://github.com") .. "/" .. repository
	local run = Process.env.GITHUB_RUN_ID
	context.repository = context.repository or repository
	context.repository_url = context.repository_url or base
	context.source_sha = context.source_sha or Process.env.CI_SOURCE_SHA or Process.env.GITHUB_SHA or "local"
	context.run_url = context.run_url or base .. "/actions" .. (if run then "/runs/" .. run else "")
	context.execution_url = context.execution_url or ""
	context.run_button = shieldcnButton("run", context, config)
	context.execution_button = shieldcnButton("execution", context, config)
	context.artifacts_button = shieldcnButton("artifacts", context, config)
	context.repository_button = shieldcnButton("repository", context, config)
	context.selected_count = context.selected_count or tostring(#keys(outcomes or {}))
	context.component_tree = componentTree(outcomes or {}, entries)
	if context.color == "success" then
		for _, entry in entries do
			if entry.color == "failure" or entry.color == "warning" then
				context.color = "warning"
				break
			end
		end
	end
	context.status_marker, context.status_alert = color(context.color or "info")
	context.result = context.result or "See the component results and next steps below."
	context.result_block = if context.color == "success"
		then context.result
		else `> [!{context.status_alert}]\n> {context.result}`
	local labels = Publication.Record(config.labels)
	local attention: { string } = {}
	for _, entry in entries do
		if entry.color ~= "warning" and entry.color ~= "failure" then
			continue
		end
		local label = entry.id
		for _, selector in keys(labels) do
			if Glob.Match(entry.id, selector) then
				label = Publication.Text(labels[selector])
				break
			end
		end
		table.insert(attention, `- [{label}](#response-{entry.index})`)
	end
	context.attention = table.concat(attention, "\n")
	local function render(node: { [string]: unknown }): string
		if node.if_value and (context[Publication.Text(node.if_value)] or "") == "" then
			return ""
		end
		local localValues = table.clone(context)
		if node.color then
			localValues.status_marker, localValues.status_alert = color(Publication.Text(node.color))
		end
		local children = Publication.Record(node.children or {})
		local names = keys(children)
		table.sort(names, function(a, b)
			local left = Publication.Record(children[a]).order or 0
			local right = Publication.Record(children[b]).order or 0
			if type(left) ~= "number" or type(right) ~= "number" then
				error("Response order must be numeric", 0)
			end
			return if left == right then a < b else left < right
		end)
		local renderedChildren: { string } = {}
		for _, name in names do
			local child = render(Publication.Record(children[name]))
			if child ~= "" then
				table.insert(renderedChildren, child)
			end
		end
		local renderedRecords: { string } = {}
		if node.records then
			local pattern = Publication.Text(node.records)
			for _, entry in entries do
				if
					not Glob.Match(entry.id, pattern)
					or (node.component and not entry.components[Publication.Text(node.component)])
				then
					continue
				end
				local label = entry.id
				for _, selector in keys(labels) do
					if Glob.Match(entry.id, selector) then
						label = Publication.Text(labels[selector])
						break
					end
				end
				local marker = color(entry.color)
				table.insert(
					renderedRecords,
					Responses.Fill(Responses.Template("records.record"), {
						index = tostring(entry.index),
						status_marker = marker,
						label = label,
						components = table.concat(keys(entry.components), ", "),
						markdown = entry.markdown,
					})
				)
			end
			if #renderedRecords == 0 and #renderedChildren == 0 then
				return ""
			end
		end
		localValues.children = table.concat(renderedChildren, "\n\n")
		localValues.records = table.concat(renderedRecords, "\n\n")
		local markdown = Responses.Fill(read(Publication.Text(node.markdown)), localValues)
		return (markdown:gsub("\n+$", ""))
	end
	return render(Publication.Record(Publication.Record(config.responses)[root]))
end

function Responses.Write(root: string, values: { [string]: string }, outcomes: { [string]: string }?): ()
	local markdown = Responses.Render(root, values, outcomes)
	local path = Process.env.GITHUB_STEP_SUMMARY
	if path then
		Fs.writeFile(path, markdown)
	end
	written = true
	print(`CI {root} response assembled.`)
end

function Responses.Written(): boolean
	return written
end

return Responses
