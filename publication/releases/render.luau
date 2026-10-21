-- publication/releases/render.luau
--!strict

local Render = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local C = require("../../libraries/bootstrap/canonical")
local D = require("../../libraries/bootstrap/documents")
local Json = require("../../libraries/bootstrap/json")
local Files = require("../../libraries/bootstrap/files")
local Commands = require("../../libraries/bootstrap/commands")
local Bundles = require("../../libraries/bootstrap/bundles")
local Shape = require("../../libraries/registry/shape")
local GitHub = require("../../libraries/bootstrap/github")
local History = require("./history")
local Notes = require("./notes")
local Client = require("./client")
local Distributions = require("./distributions")
local Versions = require("./versions")

--# Types

export type AssemblyOptions = {
	Archive: ((string) -> ())?,
	History: ((C.Value) -> History.Data)?,
	NotesAPI: Client.API?,
}

--# Helpers

local function text(value: C.Value): string
	return Json.String(value)
end

local function inspect(bytes: string): boolean
	if #bytes < 4 then
		return false
	end
	if bytes:sub(1, 2) == "#!" then
		return true
	end
	local data = buffer.fromstring(bytes)
	local function u16(offset: number, little: boolean): number
		local value = buffer.readu16(data, offset)
		return if little then value else bit32.bor(bit32.lshift(bit32.band(value, 255), 8), bit32.rshift(value, 8))
	end
	local function u32(offset: number, little: boolean): number
		local value = buffer.readu32(data, offset)
		return if little then value else bit32.byteswap(value)
	end
	if bytes:sub(1, 4) == "\127ELF" then
		if #bytes < 18 then
			return false
		end
		local little = bytes:byte(6) == 1
		local kind = u16(16, little)
		if kind == 2 then
			return true
		end
		local wide = bytes:byte(5) == 2
		if kind ~= 3 or not (wide or bytes:byte(5) == 1) or #bytes < 64 then
			return false
		end
		local offset = if not wide
			then u32(28, little)
			elseif little then u32(32, true) + u32(36, true) * 4294967296
			else u32(36, false) + u32(32, false) * 4294967296
		local size, count = u16(if wide then 54 else 42, little), u16(if wide then 56 else 44, little)
		if size < 4 or offset > 9007199254740991 or offset + size * count > #bytes then
			return false
		end
		for index = 0, count - 1 do
			if u32(offset + index * size, little) == 3 then
				return true
			end
		end
		return false
	end
	if bytes:sub(1, 2) == "MZ" and #bytes >= 64 then
		local offset = u32(60, true)
		return offset + 24 <= #bytes and u32(offset, true) == 0x4550 and bit32.band(u16(offset + 22, true), 0x2000) == 0
	end
	local magic = u32(0, false)
	if #bytes >= 16 and table.find({ 0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe }, magic) then
		return u32(12, magic == 0xcefaedfe or magic == 0xcffaedfe) == 2
	end
	return false
end

--# Functions

function Render.Executable(bytes: string): boolean
	local ok, executable = pcall(inspect, bytes)
	return ok and executable
end

function Render.Escape(value: string): string
	local replacements: { [string]: string } =
		{ ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }
	return (value:gsub("[&<>\"']", replacements))
end

function Render.SVG(rows: { C.Value }, expanded: boolean?): string
	local columns, characters = 1, 116
	local labels: { string } = {}
	for _, row in rows do
		columns = math.max(columns, #D.Items(row, "before"), #D.Items(row, "after"))
		local refs = {}
		for _, ref in D.Items(row, "refs") do
			table.insert(refs, text(ref))
		end
		local label = D.Text(row, "sha"):sub(1, 7)
			.. "  "
			.. D.Text(row, "subject")
			.. (if D.Get(row, "context") == true then " [range start]" else "")
			.. (if #refs > 0 then " [" .. table.concat(refs, ", ") .. "]" else "")
		table.insert(labels, label)
		if expanded then
			characters = math.max(characters, utf8.len(label) or #label)
		end
	end
	local graphWidth = 24 + columns * 22
	local width, height = graphWidth + characters * 8 + 16, math.max(64, #rows * 34 + 28)
	local colors = D.Items(D.Required(D.Read("publication/releases/ruleset.json"), "rules"), "graph_colors")
	local function color(lane: number): string
		return text(colors[lane % #colors + 1])
	end
	local content = { '<rect width="100%" height="100%" rx="8" fill="#0d1117"/>' }
	for index, row in rows do
		local lane = D.Number(row, "lane")
		local y = 28 + (index - 1) * 34
		local x = 24 + lane * 22
		for position, value in D.Items(row, "before") do
			if Json.Truthy(value) and position - 1 ~= lane then
				table.insert(
					content,
					string.format(
						'<path d="M %d %d V %d" stroke="%s" stroke-width="2"/>',
						24 + (position - 1) * 22,
						y - 17,
						y + 17,
						color(position - 1)
					)
				)
			end
		end
		if D.Get(row, "incoming") == true then
			table.insert(
				content,
				string.format('<path d="M %d %d V %d" stroke="%s" stroke-width="2"/>', x, y - 17, y, color(lane))
			)
		end
		for _, edge in D.Items(row, "edges") do
			local to = D.Number(edge, "to")
			local destination = 24 + to * 22
			table.insert(
				content,
				string.format(
					'<path d="M %d %d C %d %d, %d %d, %d %d" fill="none" stroke="%s" stroke-width="2"/>',
					x,
					y,
					x,
					y + 17,
					destination,
					y,
					destination,
					y + 17,
					color(to)
				)
			)
		end
		table.insert(
			content,
			string.format(
				'<circle cx="%d" cy="%d" r="5" fill="%s" stroke="%s" stroke-width="2"/>',
				x,
				y,
				if D.Get(row, "context") == true then "#0d1117" else color(lane),
				color(lane)
			)
		)
		local label = labels[index]
		if (utf8.len(label) or #label) > characters then
			label = label:sub(1, (utf8.offset(label, characters) or #label) - 1) .. "…"
		end
		table.insert(
			content,
			string.format(
				'<text x="%d" y="%d" fill="%s" font-family="JetBrains Mono" font-size="13">%s</text>',
				graphWidth,
				y + 5,
				if D.Get(row, "context") == true then "#8b949e" else "#e6edf3",
				Render.Escape(label)
			)
		)
	end
	return string.format(
		'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>',
		width,
		height,
		width,
		height,
		table.concat(content)
	)
end

function Render.HTML(rows: { C.Value }, version: string, sha: string): string
	local links = {}
	for index, row in rows do
		table.insert(
			links,
			string.format(
				'<a href="%s" title="%s" target="_blank" rel="noopener noreferrer" style="top:%dpx;height:34px"><span class="sr">%s</span></a>',
				Render.Escape(D.Text(row, "url")),
				Render.Escape(D.Text(row, "sha") .. "\n" .. D.Text(row, "subject")),
				(index - 1) * 34 + 11,
				Render.Escape(D.Text(row, "subject"))
			)
		)
	end
	return '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>'
		.. Render.Escape(version)
		.. " commit graph</title><style>body{background:#0d1117;color:#e6edf3;font:14px monospace;margin:24px}a{color:#58a6ff}.graph{position:relative;width:max-content}.graph>a{position:absolute;left:0;width:100%;display:block}.graph>a:hover{background:#58a6ff22;outline:1px solid #58a6ff}.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}</style><h1>"
		.. Render.Escape(version)
		.. "</h1><p>Selected source commit: "
		.. Render.Escape(sha)
		.. '</p><div class="graph">'
		.. Render.SVG(rows, true)
		.. table.concat(links)
		.. "</div></html>"
end

function Render.FinalizeAssets(root: string, metadata: C.Value, files: { string }): C.Value
	local assets: { C.Value } = {}
	local names: { [string]: boolean } = {}
	for _, file in files do
		Shape.Relative(file)
		local name = D.Text(metadata, "version") .. "-" .. assert(file:match("([^/]+)$"))
		assert(not names[name], "duplicate public asset names")
		names[name] = true
		table.insert(
			assets,
			C.Object({ path = file, name = name, sha256 = Serde.hash("sha256", Fs.readFile(root .. "/" .. file)) })
		)
	end
	metadata = D.Set(metadata, "assets", C.Array(assets))
	D.Write(root .. "/release.json", metadata)
	return metadata
end

function Render.Assemble(plan: C.Value, options: AssemblyOptions?)
	local selectedOptions: AssemblyOptions = options or {}
	local repository = GitHub.Repository()
	local repoURL = "https://github.com/" .. repository
	for _, selection in D.Items(plan, "selections") do
		local version, sha = D.Text(selection, "version"), D.Text(selection, "source_sha")
		Versions.Parse(version)
		local root = "build/releases/" .. version
		Files.Reset(root)
		Fs.writeDir(root .. "/packages")
		local targets: { C.Value } = {}
		local publicTargets: { C.Value } = {}
		for _, entry in D.Items(plan, "builds") do
			if D.Get(entry, "source_sha") ~= sha then
				continue
			end
			local name = Shape.Relative(D.Text(entry, "name"))
			local artifact = Shape.Relative(D.Text(entry, "artifact"))
			if #D.Items(plan, "builds") == 1 then
				Bundles.Normalize("build/distributions", artifact, "provenance.json")
			end
			local input = "build/distributions/" .. artifact
			local verified = Distributions.Verify(input, entry)
			Files.Copy(input, root .. "/packages/" .. name)
			local contract: { [string]: C.Value } = {}
			for _, key in
				{
					"name",
					"source_sha",
					"tree",
					"source_manifest_sha256",
					"fingerprint",
					"reuse_identity",
					"runner",
					"target",
					"accepted",
				}
			do
				contract[key] = D.Get(entry, key) or C.Missing
			end
			contract.reuse_identity = D.Get(entry, "reuse_identity") or "exact_commit"
			local target = C.Object({
				name = name,
				fingerprint = D.Required(entry, "fingerprint"),
				manifest = verified.manifest,
				tested_sha = D.Required(verified.metadata, "source_sha"),
				selected_sha = sha,
				reuse_identity = contract.reuse_identity,
			})
			table.insert(publicTargets, target)
			table.insert(targets, D.Set(target, "contract", C.Object(contract)))
		end
		assert(#targets > 0, "no selected build targets for " .. version)
		local data = if selectedOptions.History
			then selectedOptions.History(selection)
			else History.Read(selection, ".", repoURL)
		local commits = table.clone(data.commits)
		if data.context then
			table.insert(commits, data.context)
		end
		local rows = History.Layout(commits)
		Fs.writeDir(root .. "/graph")
		local pageSize =
			D.Number(D.Required(D.Read("publication/releases/ruleset.json"), "rules"), "graph_rows_per_page")
		for offset = 1, math.max(1, #rows), pageSize do
			local page = {}
			for index = offset, math.min(#rows, offset + pageSize - 1) do
				table.insert(page, rows[index])
			end
			local name = string.format("graph-%03d", math.floor((offset - 1) / pageSize) + 1)
			local svg = Render.SVG(page)
			Fs.writeFile(root .. "/graph/" .. name .. ".svg", svg)
		end
		local publicRows: { C.Value } = {}
		for _, row in rows do
			table.insert(publicRows, D.Set(D.Set(row, "email", nil), "body", nil))
		end
		D.Write(root .. "/graph.json", C.Array(publicRows))
		Fs.writeFile(root .. "/graph.html", Render.HTML(publicRows, version, sha))
		local changes = {}
		for _, commit in data.commits do
			table.insert(
				changes,
				"- ["
					.. D.Text(commit, "sha"):sub(1, 7)
					.. "]("
					.. D.Text(commit, "url")
					.. ") "
					.. Notes.Escape(D.Text(commit, "subject"))
			)
		end
		Fs.writeFile(
			root .. "/changes.md",
			"# Changes\n\n" .. table.concat(changes, "\n") .. "\n\n" .. data.stats .. "\n"
		)
		local notesAPI = selectedOptions.NotesAPI or (if Process.env.GH_TOKEN then Client.new(repository) else nil)
		assert(Process.env.GITHUB_ACTIONS ~= "true" or notesAPI, "hosted notes require GitHub PR access")
		Fs.writeFile(root .. "/notes.md", Notes.Build(selection, data, repoURL, notesAPI))
		if selectedOptions.Archive then
			selectedOptions.Archive(root)
		else
			Commands.Run("tar", {
				"--sort=name",
				"--mtime=@0",
				"--owner=0",
				"--group=0",
				"--numeric-owner",
				"--format=gnu",
				"-czf",
				root .. "/packages.tar.gz",
				"-C",
				root .. "/packages",
				".",
			})
		end
		local fields = Json.Fields(selection)

		fields.targets = C.Array(publicTargets)
		D.Write(
			root .. "/publication.json",
			C.Object({
				version = version,
				source_sha = sha,
				controller_sha = D.Required(plan, "controller_sha"),
				controller_hash = D.Required(plan, "controller_hash"),
				targets = C.Array(targets),
				contract_hash = Serde.hash("sha256", Fs.readFile("publication/releases/versions.toml")),
			})
		)
		local files = {}
		for _, target in targets do
			for _, item in D.Items(target, "manifest") do
				local path = Shape.Relative(D.Text(item, "path"))
				local input = root .. "/packages/" .. D.Text(target, "name") .. "/" .. path
				if Render.Executable(Fs.readFile(input)) then
					local file = "executables/" .. D.Text(target, "name") .. "-" .. path:gsub("/", "-")
					Files.Copy(input, root .. "/" .. file)
					table.insert(files, file)
				end
			end
		end
		Render.FinalizeAssets(root, C.Object(fields), files)
	end
end

return Render
