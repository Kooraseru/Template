-- repo/ci/github/attestations.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Process = require("@lune/process")
local Publication = require("./publication")

const ROOT = "build/repo/attestations"
const SUBJECTS = "build/repo/attestations/subjects"

local Attestations = {}

function Attestations.Enabled(): boolean
	local root = Publication.Record(Serde.decode("toml", Fs.readFile("repo/config/attestations.toml")))
	local settings = Publication.Record(root.attestations)
	for field in settings do
		if field ~= "mode" then
			error(`Unknown attestations setting {field}`, 0)
		end
	end
	if settings.mode ~= "best_effort" and settings.mode ~= "disabled" then
		error("attestations.mode must be best_effort or disabled", 0)
	end
	return settings.mode == "best_effort"
end

function Attestations.Prepare(): boolean
	if not Attestations.Enabled() then
		print("Attestations skipped: disabled by repository configuration")
		return false
	end
	if Fs.metadata(ROOT).kind == "symlink" then
		error("Refusing symlink attestation output directory", 0)
	end
	if Fs.isDir(ROOT) then
		Fs.removeDir(ROOT)
	end
	local seen: { [string]: boolean } = {}
	local subjects: { { name: string, digest: string, path: string } } = {}
	for _, value in Publication.ReadIndex("build/repo/releases/index.json", "releases") do
		local release = Publication.Record(value)
		local assets = release.assets
		if assets == nil then
			continue
		end
		if type(assets) ~= "table" then
			error("Invalid release asset records for attestation", 0)
		end
		for _, value in assets do
			local asset = Publication.Record(value)
			local name = Publication.Text(asset.name)
			local path = Publication.Text(asset.path)
			local digest = Publication.Text(asset.digest)
			if
				not name:match("^[%w][%w_.%-]*$")
				or not path:match("^build/repo/releases/[%w_./%-]+$")
				or path:find("..", 1, true)
			then
				error("Unsafe attestation subject", 0)
			end
			local bytes = Fs.readFile(path)
			if digest ~= "sha256:" .. Serde.hash("sha256", bytes) then
				error(`Attestation subject checksum mismatch: {name}`, 0)
			end
			local key = digest .. ":" .. name
			if seen[key] then
				continue
			end
			seen[key] = true
			local directory = `{SUBJECTS}/{digest:sub(8)}`
			Fs.writeDir(directory)
			local destination = `{directory}/{name}`
			Fs.writeFile(destination, bytes)
			table.insert(subjects, { name = name, digest = digest, path = destination })
		end
	end
	if #subjects == 0 then
		print("Attestations skipped: no compiled release assets")
		return false
	end
	if #subjects > 1024 then
		print(
			"::warning::Attestations skipped: GitHub's subject limit is 1024; split the asset set into smaller stages"
		)
		return false
	end
	Fs.writeFile(`{ROOT}/intent.json`, Serde.encode("json", { mode = "best_effort", subjects = subjects }))
	print(`Prepared {#subjects} verified provenance subjects; signing is handled by the native attestation adapter`)
	return true
end

function Attestations.Options(): ()
	Publication.Output("enabled", "false")
	if not Attestations.Enabled() then
		return
	end
	if not Fs.isFile(`{ROOT}/intent.json`) then
		print("Attestations skipped: no prepared subject set is available")
		return
	end
	local intent = Publication.Record(Serde.decode("json", Fs.readFile(`{ROOT}/intent.json`)))
	local subjects = intent.subjects
	if type(subjects) ~= "table" or #subjects == 0 then
		print("Attestations skipped: empty subject set")
		return
	end
	for _, value in subjects do
		local asset = Publication.Record(value)
		local path = Publication.Text(asset.path)
		if not path:match("^build/repo/attestations/subjects/[%w_./%-]+$") or path:find("..", 1, true) then
			error("Unsafe prepared attestation path", 0)
		end
		if Publication.Text(asset.digest) ~= "sha256:" .. Serde.hash("sha256", Fs.readFile(path)) then
			error("Prepared attestation subject changed after staging", 0)
		end
	end
	local repository = Process.env.GITHUB_REPOSITORY
	local workflow = Process.env.GITHUB_WORKFLOW_REF
	local runId = Process.env.GITHUB_RUN_ID
	local attempt = Process.env.GITHUB_RUN_ATTEMPT or "1"
	if not repository or not workflow or not runId then
		error("Attestation signing requires GitHub workflow context", 0)
	end
	local head = Process.exec("git", { "rev-parse", "HEAD" })
	local sha = head.stdout:gsub("%s+$", "")
	local expected = Process.env.CI_SOURCE_SHA or Process.env.GITHUB_SHA
	if not head.ok or #sha ~= 40 or not sha:match("^%x+$") or sha ~= expected then
		error("Cannot establish the exact checked-out attestation source commit", 0)
	end
	local server = Process.env.GITHUB_SERVER_URL or "https://github.com"
	local sourceUri = `git+{server}/{repository}@{sha}`
	local sourceParameters = { repository = `{server}/{repository}`, commit = sha }
	local workflowPath, workflowRef = workflow:sub(#repository + 2):match("^(.-)@(.+)$")
	if not workflowPath or not workflowRef then
		error("Invalid attestation workflow reference", 0)
	end
	local workflowParameters = { ref = workflowRef, repository = `{server}/{repository}`, path = workflowPath }
	local githubParameters = {
		event_name = Process.env.GITHUB_EVENT_NAME or Process.env.CI_EVENT,
		repository_id = Process.env.GITHUB_REPOSITORY_ID,
		repository_owner_id = Process.env.GITHUB_REPOSITORY_OWNER_ID,
		runner_environment = Process.env.RUNNER_ENVIRONMENT,
		workflowSha = Process.env.GITHUB_WORKFLOW_SHA,
	}
	local workflowSha = Process.env.GITHUB_SHA or sha
	local dependency = { uri = `git+{server}/{repository}@{workflowRef}`, digest = { gitCommit = workflowSha } }
	local dependencies = { dependency }
	if workflowSha ~= sha then
		table.insert(dependencies, { uri = sourceUri, digest = { gitCommit = sha } })
	end
	local buildDefinition = {
		buildType = "https://actions.github.io/buildtypes/workflow/v1",
		externalParameters = { source = sourceParameters, workflow = workflowParameters },
		internalParameters = { github = githubParameters },
		resolvedDependencies = dependencies,
	}
	local runDetails = {
		builder = { id = `{server}/{workflow}` },
		metadata = { invocationId = `{server}/{repository}/actions/runs/{runId}/attempts/{attempt}` },
	}
	local predicate = { buildDefinition = buildDefinition, runDetails = runDetails }
	Fs.writeFile(`{ROOT}/predicate.json`, Serde.encode("json", predicate))
	Publication.Output("predicate_path", `{ROOT}/predicate.json`)
	Publication.Output("subject_path", `{SUBJECTS}/**/*`)
	Publication.Output("enabled", "true")
end

function Attestations.Result(setup: string?, enabled: string?, outcome: string?): (string, string)
	if setup == "failure" then
		return "failed (non-blocking)", "Attestation setup failed; independent pipeline work continues."
	end
	if enabled ~= "true" then
		return "skipped", "No signing was requested or prepared; no attestation was claimed."
	end
	if outcome == "success" then
		return "passed", "GitHub generated and recorded artifact provenance."
	end
	if outcome == "failure" then
		return "failed (non-blocking)",
			"GitHub could not attest these artifacts. Check repository plan, visibility, permissions, and signing-service availability. Builds and publications continue; these artifacts are not claimed to be attested."
	end
	return "skipped", "Signing did not execute; no attestation was claimed."
end

function Attestations.Report(): ()
	local outcome, detail = Attestations.Result(
		Process.env.CI_ATTESTATION_SETUP,
		Process.env.CI_ATTESTATION_ENABLED,
		Process.env.CI_ATTESTATION_OUTCOME
	)
	if outcome == "failed (non-blocking)" then
		print(`::warning::{detail}`)
	else
		print(`Attestations: {outcome}. {detail}`)
	end
	local path = Process.env.GITHUB_STEP_SUMMARY
	if path then
		local template = Fs.readFile("repo/content/ci/attestation-summary.md")
		local text = template:gsub("{{outcome}}", outcome):gsub("{{detail}}", detail)
		local current = if Fs.isFile(path) then Fs.readFile(path) else ""
		Fs.writeFile(path, current .. "\n" .. text)
	end
end

return Attestations
