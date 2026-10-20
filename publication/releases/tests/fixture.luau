-- publication/releases/tests/fixture.luau
--!strict

local Fixture = {}

--# Modules

local Json = require("../../../libraries/bootstrap/json")
local Fs = require("@lune/fs")
local C = require("../../../libraries/bootstrap/canonical")
local D = require("../../../libraries/bootstrap/documents")
local Git = require("../../../libraries/bootstrap/git")
local Files = require("../../../libraries/bootstrap/files")
local Commands = require("../../../libraries/bootstrap/commands")

--# Types

export type Repository = { Root: string, Commits: { [string]: string } }

--# Functions

function Fixture.Create(): Repository
	local root = "build/tests/releases/history"
	Files.Reset(root)
	Git.Bytes({ "init", "--initial-branch=source", root })
	Git.Bytes({ "config", "user.name", "Test Committer" }, root)
	Git.Bytes({ "config", "user.email", "committer@example.test" }, root)
	Git.Bytes({ "config", "commit.gpgsign", "false" }, root)
	local commits: { [string]: string } = {}
	local cases = D.Required(D.Read("publication/releases/ruleset.json"), "cases")
	for _, entry in D.Items(D.Required(cases, "history"), "commits") do
		if D.Get(entry, "parent") then
			Git.Bytes({ "checkout", "-B", D.Text(entry, "branch"), assert(commits[D.Text(entry, "parent")]) }, root)
		elseif next(commits) then
			Git.Bytes({ "checkout", D.Text(entry, "branch") }, root)
		end
		if D.Get(entry, "merge") then
			Git.Bytes({ "merge", "--no-ff", "--no-commit", assert(commits[D.Text(entry, "merge")]) }, root)
		end
		if D.Get(entry, "mailmap") then
			Fs.writeFile(root .. "/.mailmap", D.Text(entry, "mailmap"))
		end
		local id = D.Text(entry, "id")
		Fs.writeFile(root .. "/" .. id .. ".txt", D.Text(entry, "message"))
		local files = D.Get(entry, "files")
		if files then
			for _, field in Json.Object(files).entries do
				local name = assert(C.Text(field.key))
				local path = root .. "/" .. name
				local parent = path:match("^(.*)/[^/]+$")
				if parent then
					Fs.writeDir(parent)
				end
				Fs.writeFile(path, Json.String(field.value))
			end
		end
		Git.Bytes({ "add", "." }, root)
		Commands.Run("git", { "commit", "-m", D.Text(entry, "message") }, nil, root, {
			GIT_AUTHOR_NAME = D.Text(entry, "name"),
			GIT_AUTHOR_EMAIL = D.Text(entry, "email"),
			GIT_AUTHOR_DATE = "2026-10-14T00:00:00Z",
			GIT_COMMITTER_DATE = "2026-10-14T00:00:00Z",
		})
		commits[id] = Git.Text({ "rev-parse", "HEAD" }, root)
	end
	return { Root = root, Commits = commits }
end

function Fixture.Expand(value: C.Value, fixture: Repository): C.Value
	local expanded = assert(C.Encode(value)):gsub("%$([a-z]+)", function(key)
		return fixture.Commits[key] or ("$" .. key)
	end)
	return C.Decode(expanded)
end

return Fixture
