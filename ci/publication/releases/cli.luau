-- ci/publication/releases/cli.luau
--!strict

local Releases = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local C = require("../../utilities/canonical")
local D = require("../../utilities/documents")
local Commands = require("../../utilities/commands")
local Git = require("../../utilities/git")
local Files = require("../../utilities/files")
local Outputs = require("../../utilities/outputs")
local GitHub = require("../../utilities/github")
local Shape = require("../../utilities/shape")
local Hosted = require("../../security/receipts/hosted")
local Distributions = require("./distributions")
local Render = require("./render")
local Publish = require("./publish")
local Protection = require("./protection")
local Client = require("./client")

--# Functions

function Releases.Prepare()
	local entry = C.Decode(assert(Process.env.CI_BUILD_SPEC))
	local sha = Git.FullSHA(D.Text(entry, "source_sha"))
	local reused = false
	local acceptance = D.Get(entry, "accepted")
	if acceptance then
		local staged = "build/accepted-distributions/" .. Shape.Relative(D.Text(entry, "artifact"))
		if Fs.isDir(staged) then
			Files.Copy(staged, "build/artifacts")
			local logs = "build/accepted-logs/build-logs-" .. sha .. "-" .. Shape.Relative(D.Text(entry, "name"))
			if Fs.isDir(logs) then
				Files.Copy(logs, "build/logs")
			end
		else
			Hosted.Restore(entry, "build/artifacts")
		end
		Distributions.Verify("build/artifacts", entry)
		reused = true
	end
	if not reused and D.Get(entry, "cache_run") ~= "" and Fs.isFile("build/artifacts/provenance.json") then
		local ok, failure = pcall(Distributions.Verify, "build/artifacts", entry)
		reused = ok
		if not ok then
			Files.Reset("build/artifacts")
			Fs.writeDir("build/reports")
			Fs.writeFile("build/reports/rejected-cache.txt", tostring(failure))
		end
	end
	D.Write("build/tmp/releases/build-spec.json", entry)
	local relative = "build/tmp/source/" .. sha
	local source = Process.cwd:gsub("\\", "/"):gsub("/$", "") .. "/" .. relative
	local worktree = Process.env.ACT == "true" and sha == Process.env.CI_TESTED_SHA
	if worktree then
		source = Process.cwd
	end
	if not reused and not worktree then
		Files.Reset(relative)
		Git.Bytes({ "clone", "--no-hardlinks", "--no-checkout", Process.cwd, source })
		Git.Bytes({ "-C", source, "checkout", "--detach", sha })
		local origin = Commands.Execute("git", { "remote", "get-url", "origin" })
		if origin.ok then
			Git.Bytes({ "-C", source, "remote", "set-url", "origin", (origin.stdout:gsub("%s+$", "")) })
		end
		Fs.writeDir(source .. "/build")
	end
	Outputs.Write(Process.env.GITHUB_OUTPUT, { reused = tostring(reused), source_dir = source })
end

function Releases.Run(provided: { string }?)
	local args = provided or Process.args
	local operation = args[1]
	if operation == "prepare" then
		Releases.Prepare()
	elseif operation == "verify" then
		Distributions.Verify(assert(args[2]), C.Decode(assert(Process.env.CI_BUILD_SPEC)))
	elseif operation == "assemble" then
		Render.Assemble(D.Read("build/tmp/releases/plan.json"))
	elseif operation == "publish" then
		Publish.Run()
	elseif operation == "protect" then
		Protection.Require(assert(args[2] or Process.env.GITHUB_REPOSITORY))
	elseif operation == "attest-protection" then
		assert(
			Process.env.ACT ~= "true" and Process.env.GITHUB_ACTIONS ~= "true" and GitHub.IsAdmin(GitHub.Actor()),
			"enroll protection outside CI using administrator login"
		)
		local repository = GitHub.Repository()
		local api = Client.new(repository)
		local sets: { C.Value } = {}
		for _, summary in api.Pages("/rulesets") do
			table.insert(sets, (assert(api.Request("/rulesets/" .. D.Number(summary, "id")))))
		end
		assert(Protection.Valid(sets), "required source protections absent")
		local snapshot = C.Object({ repository = repository, rulesets = C.Array(sets) })
		D.Write("build/reports/source-protection-attestation.json", snapshot)
		Commands.Run(
			"gh",
			{ "variable", "set", "CI_SOURCE_PROTECTION", "--repo", repository },
			assert(C.Encode(snapshot))
		)
	else
		error("unknown release operation: " .. tostring(operation))
	end
end

return Releases
