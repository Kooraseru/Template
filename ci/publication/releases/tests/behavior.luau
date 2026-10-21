-- ci/publication/releases/tests/behavior.luau
--!strict

local Test = require("../../../libraries/testing/test")

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local C = require("../../../libraries/bootstrap/canonical")
local D = require("../../../libraries/bootstrap/documents")
local Json = require("../../../libraries/bootstrap/json")
local Files = require("../../../libraries/bootstrap/files")
local Versions = require("../versions")
local Fixture = require("./fixture")
local History = require("../history")
local Notes = require("../notes")
local Render = require("../render")
local Protection = require("../protection")
local Distributions = require("../distributions")
local Client = require("../client")
local GitHub = require("../../../libraries/bootstrap/github")

--# Types

type Input = { Kind: string, Scenario: C.Value? }

--# Helpers

local fixture: Fixture.Repository? = nil

local function repository(): Fixture.Repository
	fixture = fixture or Fixture.Create()
	return assert(fixture)
end

local function execute(input: Input): boolean
	if input.Kind == "history" then
		local source = repository()
		local rules = D.Required(D.Required(D.Read("ci/publication/releases/ruleset.json"), "cases"), "history")
		local data = History.Read(
			C.Object({ from = source.Commits.root, source_sha = source.Commits.merge }),
			source.Root,
			"https://github.com/example/project"
		)
		assert(#data.commits == D.Number(rules, "range_count"))
		assert(D.Equal(D.From(data.contributors), D.Get(rules, "contributors")))
		assert(data.context and D.Get(data.context, "sha") == source.Commits.root)
		local commits = table.clone(data.commits)
		table.insert(commits, assert(data.context))
		local rows = History.Layout(commits)
		local decodedRows = Json.Array(C.Decode(assert(C.Encode(C.Array(commits)))))
		assert(
			D.Equal(C.Array(rows), C.Array(History.Layout(decodedRows))),
			"graph topology changed after JSON transport"
		)
		local merge = false
		for _, row in rows do
			merge = merge or #D.Items(row, "edges") == 2
		end
		assert(merge and Render.SVG(rows):find("&lt;safe&gt;", 1, true))
		assert(not Render.HTML(rows, "1.0.0-pre.1", source.Commits.merge):find("<script", 1, true))
		assert(
			#History.Read(C.Object({ from = "beginning", source_sha = source.Commits.merge }), source.Root).commits
				== D.Number(rules, "beginning_count")
		)
		assert(
			#History.Read(C.Object({ from = source.Commits.root, source_sha = source.Commits.root }), source.Root).contributors
				== 0
		)
		return true
	elseif input.Kind == "selection" then
		local source = repository()
		local document = {
			releases = {
				{ version = "1.2.0", commit = source.Commits.merge, from = source.Commits.root },
				{ version = "1.3.0-pre.1", commit = source.Commits.merge },
			},
		}
		local selected =
			Versions.Select(document, { release_output = "Publish Pre-Release" }, source.Commits.merge, source.Root)
		assert(#selected == 1 and selected[1].version == "1.3.0-pre.1")
		assert(
			Versions.Select(
				document,
				{ release_version = "1.2.0", release_commit = source.Commits.merge },
				source.Commits.merge,
				source.Root
			)[1].from == source.Commits.root
		)
		assert(
			Versions.Select(
				{ releases = {} },
				{ release_version = "1.3.0", release_commit = source.Commits.merge },
				source.Commits.merge,
				source.Root
			)[1].type == "Release"
		)
		assert(
			#document.releases == 2 and #Versions.Validate({ releases = {} }, source.Commits.merge, source.Root) == 0
		)
		assert(not pcall(Versions.Select, document, { release_version = "1.2.0" }, source.Commits.merge, source.Root))
		assert(
			not pcall(
				Versions.Select,
				{ releases = {} },
				{ release_output = "Publish Release" },
				source.Commits.merge,
				source.Root
			)
		)
		return true
	elseif input.Kind == "notes" then
		local repo = "https://github.com/example/project"
		local pr = C.Object({
			number = 17,
			title = "Fix behavior",
			user = C.Object({ login = "author" }),
			merged_at = "2026-01-01",
			merge_commit_sha = "merge",
			base = C.Object({ ref = "source", repo = C.Object({ html_url = repo }) }),
		})
		local data: History.Data = {
			commits = {},
			contributors = { "Ordinary author" },
			coauthors = { "Coauthor" },
			stats = "",
			shortstat = "",
		}
		for _, sha in { "merge", "member", "direct" } do
			table.insert(data.commits, C.Object({ sha = sha, subject = sha, url = repo .. "/commit/" .. sha }))
		end
		local api: Client.API = {
			Request = function()
				error("unexpected API request")
			end,
			Bytes = function()
				error("unexpected byte request")
			end,
			JSON = function()
				error("unexpected mutation")
			end,
			Pages = function(route)
				return if route:find("direct", 1, true)
					then {}
					else { pr, D.Set(D.Set(pr, "number", 18), "merged_at", C.Null) }
			end,
		}
		local selection = C.Object({ from = "beginning", source_sha = string.rep("a", 40) })
		local body = Notes.Build(selection, data, repo, api)
		local _, count = body:gsub("%[#17%]", "")
		assert(
			count == 1
				and body:find("by @author in [#17]", 1, true)
				and body:find("[direct]", 1, true)
				and not body:find("[member]", 1, true)
		)
		assert(
			body:find("Co-authored-by: Coauthor", 1, true)
				and not body:find("Ordinary author", 1, true)
				and not body:find("## Contributors", 1, true)
		)
		local empty = Notes.Build(
			selection,
			{ commits = {}, coauthors = {}, contributors = {}, stats = "", shortstat = "" },
			repo,
			nil
		)
		assert(empty:find("No changes in this range.", 1, true) and not empty:find("Co-authored-by:", 1, true))
		return true
	elseif input.Kind == "svg" then
		local svg = Render.SVG({})
		assert(svg:find("<svg", 1, true), "missing SVG release graph")
		return true
	elseif input.Kind == "assembly" then
		local source = repository()
		local sha = source.Commits.merge
		local version = "9.8.7-pre.6"
		local artifact = "distribution-" .. sha .. "-fixture"
		local inputRoot = "build/distributions/" .. artifact
		Files.Reset(inputRoot)
		local fingerprint = Serde.hash("sha256", "assembly fixture")
		D.Write(
			inputRoot .. "/provenance.json",
			C.Object({ source_sha = sha, fingerprint = fingerprint, target = "fixture" })
		)
		Fs.writeFile(inputRoot .. "/distribution.tar.gz", "payload")
		Fs.writeFile(inputRoot .. "/runner.sh", "#!/bin/sh\necho fixture\n")
		local manifest: { C.Value } = {}
		for _, name in { "provenance.json", "distribution.tar.gz", "runner.sh" } do
			table.insert(
				manifest,
				C.Object({ path = name, sha256 = Serde.hash("sha256", Fs.readFile(inputRoot .. "/" .. name)) })
			)
		end
		D.Write(inputRoot .. "/manifest.json", C.Array(manifest))
		local selection = Versions.Validate({ releases = { { version = version, commit = sha } } }, sha, source.Root)[1]
		local entry = C.Object({
			name = "fixture",
			source_sha = sha,
			artifact = artifact,
			fingerprint = fingerprint,
			accepted = C.Object({ release_id = 1, source_sha = sha }),
		})
		local plan = C.Object({
			controller_sha = string.rep("a", 40),
			controller_hash = string.rep("b", 64),
			selections = C.Array({ D.From(selection) }),
			builds = C.Array({ entry }),
		})
		local noNetwork: Client.API = {
			Request = function()
				error("assembly fixture must not contact GitHub")
			end,
			Bytes = function()
				error("assembly fixture must not download")
			end,
			JSON = function()
				error("assembly must not publish")
			end,
			Pages = function()
				return {}
			end,
		}
		local previousRepository = GitHub.Repository
		GitHub.Repository = function()
			return "example/project"
		end
		local ok, failure = pcall(function()
			local options: Render.AssemblyOptions = {
				NotesAPI = noNetwork,
				History = function(selected)
					return History.Read(selected, source.Root, "https://github.com/example/project")
				end,
				Archive = function(root)
					Fs.writeFile(root .. "/packages.tar.gz", "deterministic archive fixture")
				end,
			}
			Render.Assemble(plan, options)
			local root = "build/releases/" .. version
			local before = Fs.readFile(root .. "/release.json")
			assert(not before:find("release_id", 1, true))
			assert(#D.Items(D.Read(root .. "/release.json"), "assets") == 1)
			entry = D.Set(entry, "accepted", C.Object({ release_id = 2, source_sha = sha }))
			plan = D.Set(D.Set(plan, "controller_sha", string.rep("c", 40)), "builds", C.Array({ entry }))
			Render.Assemble(plan, options)
			assert(Fs.readFile(root .. "/release.json") == before, "restaging changed public release metadata")
			local internal = D.Items(D.Read(root .. "/publication.json"), "targets")[1]
			assert(D.Get(D.Required(D.Required(internal, "contract"), "accepted"), "release_id") == 2)
		end)
		GitHub.Repository = previousRepository
		assert(ok, tostring(failure))
		return true
	elseif input.Kind == "provenance" then
		local scenario = assert(input.Scenario)
		local root = "build/tests/provenance"
		Files.Reset(root)
		local source = string.rep("a", 40)
		local fingerprint = Serde.hash("sha256", "inputs")
		local metadata = C.Object({ source_sha = source, fingerprint = fingerprint, target = "linux" })
		local patch = D.Get(scenario, "patch")
		if patch then
			for key, value in Json.Fields(patch) do
				metadata = D.Set(metadata, key, value)
			end
		end
		D.Write(root .. "/provenance.json", metadata)
		Fs.writeFile(root .. "/distribution.tar.gz", "payload")
		local manifest: { C.Value } = {}
		for _, name in { "provenance.json", "distribution.tar.gz" } do
			table.insert(
				manifest,
				C.Object({ path = name, sha256 = Serde.hash("sha256", Fs.readFile(root .. "/" .. name)) })
			)
		end
		D.Write(root .. "/manifest.json", C.Array(manifest))
		if D.Get(scenario, "corrupt") == true then
			Fs.writeFile(root .. "/distribution.tar.gz", "corrupted")
		end
		if D.Get(scenario, "extra") == true then
			Fs.writeFile(root .. "/unlisted.txt", "unlisted")
		end
		return (
			pcall(
				Distributions.Verify,
				root,
				C.Object({ name = "linux", source_sha = source, fingerprint = fingerprint })
			)
		)
	elseif input.Kind == "protection" then
		local protection = D.Required(D.Read("ci/publication/releases/ruleset.json"), "protection")
		local sets: { C.Value } = { D.Required(protection, "source_checks"), D.Required(protection, "source_admins") }
		assert(Protection.Valid(sets) and not Protection.Valid({ sets[1] }))
		local actors = C.Array({ C.Object({ actor_id = 5, actor_type = "RepositoryRole", bypass_mode = "always" }) })
		sets[1] = D.Set(sets[1], "bypass_actors", actors)
		sets[2] = D.Set(sets[2], "bypass_actors", actors)
		assert(Protection.Valid(sets))
		for _, index in { 1, 2 } do
			local unsafe = table.clone(sets)
			unsafe[index] = D.Set(
				unsafe[index],
				"bypass_actors",
				C.Array({ C.Object({ actor_id = 4, actor_type = "RepositoryRole", bypass_mode = "always" }) })
			)
			assert(not Protection.Valid(unsafe))
		end
		return true
	elseif input.Kind == "visibility" then
		local scenario = assert(input.Scenario)
		local protection = D.Required(D.Read("ci/publication/releases/ruleset.json"), "protection")
		local sets: { C.Value } = {}
		local live: { C.Value } = {}
		for index, key in { "source_checks", "source_admins" } do
			local set = D.Set(D.Set(D.Required(protection, key), "id", index), "updated_at", "2026-10-14T00:00:00Z")
			table.insert(sets, set)
			table.insert(live, D.Set(set, "bypass_actors", nil))
		end
		if D.Get(scenario, "changed_time") == true then
			live[1] = D.Set(live[1], "updated_at", "2026-10-14T01:00:00Z")
		end
		if D.Get(scenario, "changed_rules") == true then
			live[1] = D.Set(live[1], "rules", C.Array({}))
		end
		if D.Get(scenario, "unsafe") == true then
			sets[1] = D.Set(
				sets[1],
				"bypass_actors",
				C.Array({ C.Object({ actor_id = 4, actor_type = "RepositoryRole", bypass_mode = "always" }) })
			)
		end
		local snapshot = if D.Get(scenario, "missing") == true
			then nil
			else C.Object({

				repository = if D.Get(scenario, "wrong_repository") == true
					then "other/repository"
					else "owner/project",
				rulesets = C.Array(sets),
			})
		return (
			pcall(function()
				assert(Protection.Valid(Protection.Verified(live, snapshot, "owner/project")))
			end)
		)
	end
	error("unknown behavior case")
end

local function cases(): { Test.Case<Input, boolean> }
	local result: { Test.Case<Input, boolean> } = {}
	for _, kind in { "history", "selection", "notes", "svg", "assembly", "protection" } do
		table.insert(result, { Name = kind, Input = { Kind = kind }, Expected = true })
	end
	local definitions = D.Required(D.Read("ci/publication/releases/ruleset.json"), "cases")
	for _, group in { { "provenance", "provenance" }, { "visibility", "protection_visibility" } } do
		for _, scenario in D.Items(definitions, group[2]) do
			table.insert(result, {
				Name = D.Text(scenario, "name"),
				Input = { Kind = group[1], Scenario = scenario },
				Expected = D.Get(scenario, "valid") == true,
			})
		end
	end
	return result
end

--# Declaration

local definition: Test.Definition<Input, boolean> = { Name = "Release behavior", Execute = execute, Cases = cases() }

return Test.new(definition)
