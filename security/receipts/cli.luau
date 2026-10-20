-- security/receipts/cli.luau
--!strict

local Receipts = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local D = require("../../libraries/bootstrap/documents")
local C = require("../../libraries/bootstrap/canonical")
local Json = require("../../libraries/bootstrap/json")
local Git = require("../../libraries/bootstrap/git")
local GitHub = require("../../libraries/bootstrap/github")
local Native = require("../../libraries/bootstrap/native")
local Commands = require("../../libraries/bootstrap/commands")
local Base64 = require("../../libraries/bootstrap/base64")
local Outputs = require("../../libraries/bootstrap/outputs")
local Bundles = require("../../libraries/bootstrap/bundles")
local Shape = require("../../libraries/registry/shape")
local Stdio = require("@lune/stdio")
local Client = require("../../publication/releases/client")
local Resolve = require("../../publication/releases/resolve")
local Request = require("../../.github/integration/request")
local SourceApproval = require("../../.github/integration/source-approval")
local Identity = require("./identity")
local Collection = require("./collection")
local Hosted = require("./hosted")
local Verification = require("./verification")
local Authentication = require("./authentication")

--# Helpers

local function localExecution(): boolean
	return Process.env.ACT == "true" or Process.env.GITHUB_ACTIONS ~= "true"
end

local function event(): C.Value
	local path = Process.env.GITHUB_EVENT_PATH
	return if path and path ~= "" then D.Read(path) else C.Object({})
end

local function api(): Client.API
	return Client.new(GitHub.Repository())
end

local function fetch(sha: string, token: string)
	Git.Bytes({ "fetch", "--no-tags", "origin", Git.FullSHA(sha) }, nil, {
		GIT_CONFIG_COUNT = "1",
		GIT_CONFIG_KEY_0 = "http.https://github.com/.extraheader",
		GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic " .. Base64.Encode("x-access-token:" .. token),
	})
end

local function outsideExecution()
	assert(
		Process.env.ACT ~= "true" and Process.env.GITHUB_ACTIONS ~= "true",
		"run this operation outside execution environments"
	)
end

local function parent(path: string): string
	return path:match("^(.*)[/\\][^/\\]+$") or "."
end

local function storeCollection(arguments: { string })
	local plan = D.Read(arguments[2] or "build/tmp/releases/plan.json")
	local context = D.Get(plan, "context") or D.Read("build/tmp/receipts/context.json")
	local distributions, logs = arguments[3] or "build/distributions", arguments[4] or "build/validation-logs"
	local destination = arguments[5] or "build/receipts"
	local receipt = Collection.Collect(plan, distributions, logs, context)
	Collection.Bundle(destination .. "/bundle", receipt, distributions, logs)
	Commands.Run("tar", { "-czf", destination .. "/bundle.tar.gz", "-C", destination .. "/bundle", "." })
	receipt = D.Set(receipt, "bundle_sha256", Serde.hash("sha256", Fs.readFile(destination .. "/bundle.tar.gz")))
	Collection.VerifyBundle(destination .. "/bundle", receipt)
	D.Write(
		destination .. "/receipt.json",
		C.Object({ receipt = receipt, authentication = C.Object({ kind = "claim" }) })
	)
end

--# Functions

function Receipts.Authorize()
	local localRun = localExecution()
	if not localRun then
		Hosted.AssertAdminWriters()
	end
	local dispatch = Process.env.GITHUB_EVENT_NAME == "workflow_dispatch"
	local controls = Request.Read()
	local rawPR = D.Get(event(), "pull_request")
	local number = if dispatch
		then Request.ParsePR(controls.pull_request)
		elseif rawPR then D.Number(rawPR, "number")
		else tonumber(Process.env.CI_RECEIPT_PR or "0") or 0
	local head = Git.Text({ "rev-parse", "HEAD" })
	local tested = Process.env.CI_TESTED_SHA or head
	local pr: C.Value
	if localRun then
		pr = D.Get(event(), "receipt_context") or C.Object({ number = number, head_sha = tested, base_sha = head })
		tested = D.Text(pr, "head_sha")
	elseif number > 0 then
		pr = Hosted.CurrentPR(number)
		tested = D.Text(pr, "head_sha")
	else
		pr = C.Object({ number = 0, head_sha = tested, base_sha = tested })
	end
	local approval = if localRun then nil else SourceApproval.Read()
	local bootstrap = not localRun
		and dispatch
		and Process.env.GITHUB_REF ~= "refs/heads/source"
		and number > 0
		and D.Get(pr, "head_sha") == Process.env.GITHUB_SHA
		and Hosted.PredatesContract(D.Text(pr, "base_sha"))
	if not localRun and dispatch then
		assert(
			GitHub.IsAdmin(GitHub.Actor()) and (Process.env.GITHUB_REF == "refs/heads/source" or bootstrap),
			"hosted validation requires an administrator and source controller"
		)
	end
	if not localRun and tested ~= head then
		fetch(tested, assert(Process.env.GH_TOKEN))
	end
	local context = C.Object({
		repository = GitHub.Repository(),
		tested_sha = tested,
		pr = pr,
		requested = localRun or dispatch or approval ~= nil,
		["local"] = localRun,
		bootstrap = bootstrap,
		controls = D.From(controls),
		source_authorization = if approval then D.From(approval) else C.Missing,
		diagnostic = localRun or (dispatch and Request.Diagnostic(controls)),
		event = Process.env.GITHUB_EVENT_NAME or "local",
	})
	D.Write("build/tmp/receipts/context.json", context)
	Outputs.Write(Process.env.GITHUB_ENV, {
		CI_TESTED_SHA = tested,
		CI_VALIDATION_REQUESTED = tostring(D.Get(context, "requested")),
		CI_RECEIPT_PR = tostring(number),
	})
	Outputs.Write(Process.env.GITHUB_OUTPUT, { requested = tostring(D.Get(context, "requested")), tested_sha = tested })
end

function Receipts.Plan()
	local context = D.Read("build/tmp/receipts/context.json")
	local plan = D.Set(D.Read("build/tmp/releases/plan.json"), "context", context)
	plan = D.Set(plan, "tested_sha", D.Required(context, "tested_sha"))
	local controls = D.Required(context, "controls")
	local localRun = D.Get(context, "local") == true
	if not localRun and not D.Text(controls, "cache_policy"):match("^Rebuild") then
		local pr = D.Required(context, "pr")
		local discovered = Hosted.Discover(plan, if D.Number(pr, "number") > 0 then pr else nil, true)
		plan = discovered.Plan
		D.Write("build/receipts/rejected-staging.json", D.From(discovered.Rejected))
	end
	local builds = D.Items(plan, "builds")
	local complete, anyAccepted = true, false
	local names: { [string]: boolean }? = nil
	if Process.env.CI_LOCAL_TARGETS then
		assert(localRun, "local target selection requires local execution")
		names = {}
		for _, raw in Json.Array(C.Decode(Process.env.CI_LOCAL_TARGETS)) do
			names[Json.String(raw)] = true
		end
		assert(next(names), "empty local target selection")
		for name in names do
			local found = false
			for _, entry in builds do
				found = found or D.Get(entry, "name") == name
			end
			assert(found, "unknown local target selection")
		end
	end
	local executing: { C.Value } = {}
	local requiredImages: { [string]: boolean } = {}
	for _, entry in builds do
		local accepted = D.Get(entry, "accepted") ~= nil
		complete = complete and accepted
		anyAccepted = anyAccepted or accepted
		if
			not localRun or (D.Text(entry, "runner"):match("^ubuntu") and (not names or names[D.Text(entry, "name")]))
		then
			table.insert(executing, entry)
			if not accepted then
				requiredImages[D.Text(entry, "image_artifact")] = true
			end
		end
	end
	local operation = D.Text(controls, "operation")
	assert(
		(operation ~= "Publish" and D.Text(controls, "cache_policy") ~= "Require stored results") or complete,
		"publish requires matching accepted cached outputs; run Build first"
	)
	local run = D.Get(context, "requested") == true or complete
	local images: { C.Value } = {}
	if run and operation ~= "Validate" and operation ~= "Publish" then
		for _, image in D.Items(plan, "images") do
			if
				D.Text(controls, "images") ~= "Required by selected builds" or requiredImages[D.Text(image, "artifact")]
			then
				table.insert(images, image)
			end
		end
	end
	plan = D.Set(plan, "images", C.Array(images))
	D.Write("build/tmp/releases/plan.json", plan)
	local outputs = D.Read("build/tmp/releases/outputs.json")
	local disabled = C.Object({ name = "disabled", runner = "ubuntu-latest", artifact = "disabled", input_ref = "" })
	local fields: { [string]: C.Value } = {
		images_enabled = tostring(#images > 0),
		image_matrix = assert(C.Encode(C.Object({ include = C.Array(if #images > 0 then images else { disabled }) }))),
		build_matrix = assert(C.Encode(C.Object({ include = C.Array(if run then executing else { disabled }) }))),
		build_requested = tostring(run),
		receipt_ready = tostring(complete),
		release_enabled = tostring(
			run and operation ~= "Validate" and #D.Items(plan, "selections") > 0 and #executing == #builds
		),
		local_execution = tostring(localRun),
		accepted_available = tostring(anyAccepted),
	}
	for key, value in fields do
		outputs = D.Set(outputs, key, value)
	end
	D.Write("build/tmp/releases/outputs.json", outputs)
end

function Receipts.Execution()
	local spec = C.Decode(assert(Process.env.CI_BUILD_SPEC))
	local fields = Json.Fields(D.From(Identity.Read(D.Text(spec, "source_sha"))))
	fields.diagnostic = localExecution()
	local os = if Process.os == "windows" then "win32" elseif Process.os == "macos" then "darwin" else "linux"
	local arch = if Process.arch == "aarch64" then "arm64" else "x64"
	local execution: C.Value = C.Object({ kind = "native", os = os, arch = arch })
	if Json.Truthy(D.Get(spec, "image")) then
		local image = D.Read("build/selected-image/image.json")
		assert(
			D.Text(image, "id"):match("^sha256:[a-f0-9]+$")
				and #D.Text(image, "id") == 71
				and D.Text(image, "os") .. "/" .. D.Text(image, "architecture") == D.Text(spec, "platform"),
			"actual image identity or platform mismatch"
		)
		execution = C.Object({
			kind = "container",
			os = "linux",
			arch = if D.Text(spec, "platform"):match("arm64$") then "arm64" else "x64",
			host_os = os,
			host_arch = arch,
			image_archive_sha256 = Serde.hash("sha256", Fs.readFile("build/selected-image/image.tar")),
			image_record = image,
		})
	end
	local probes: { C.Value } = {}
	for _, file in Bundles.Manifest("build/logs").items do
		if D.Text(file, "path"):match("^probe%-%d+%.log$") then
			table.insert(probes, file)
		end
	end
	execution = D.Set(execution, "probe_logs", C.Array(probes))
	execution = D.Set(execution, "runtime", "Lune 0.10.5")

	fields.fingerprint = D.Required(spec, "fingerprint")
	fields.target = D.Required(spec, "name")
	fields.controller_sha = Process.env.GITHUB_SHA or "local"
	fields.execution = execution
	fields.resolved_fingerprint = C.Hash(C.Object({ inputs = D.Required(spec, "fingerprint"), execution = execution }))
	D.Write("build/tmp/releases/execution.json", C.Object(fields))
end

function Receipts.Report()
	local plan = D.Read("build/tmp/releases/plan.json")
	local context = D.Required(plan, "context")
	assert(
		Process.env.ACT ~= "true"
			and table.find({ "workflow_dispatch", "push" }, Process.env.GITHUB_EVENT_NAME or "")
			and (Process.env.GITHUB_EVENT_NAME ~= "push" or D.Get(context, "source_authorization"))
			and (Process.env.GITHUB_REF == "refs/heads/source" or D.Get(context, "bootstrap") == true)
			and GitHub.IsAdmin(GitHub.Actor()),
		"trusted admin source workflow required"
	)
	local envelope = D.Read("build/receipts/receipt.json")
	local receipt = D.Set(D.Required(envelope, "receipt"), "comparison", C.Array({}))
	Hosted.FreshPR(receipt)
	envelope = D.Set(envelope, "receipt", receipt)
	envelope = D.Set(
		envelope,
		"authentication",
		C.Object({
			kind = "hosted",
			run_id = assert(Process.env.GITHUB_RUN_ID),
			controller_sha = assert(Process.env.GITHUB_SHA),
			bootstrap = if D.Get(context, "bootstrap") == true then true else C.Missing,
		})
	)
	D.Write("build/receipts/receipt.json", envelope)
	local release = Hosted.Upload(envelope, "build/receipts/bundle.tar.gz")
	D.Write(
		"build/receipts/acceptance.json",
		C.Object({ release_id = D.Required(release, "id"), differences = C.Array({}) })
	)
	local archive: C.Value? = nil
	for _, asset in D.Items(release, "assets") do
		if D.Get(asset, "name") == "bundle.tar.gz" then
			archive = asset
		end
	end
	assert(archive, "staging archive missing")
	local builds: { C.Value } = {}
	for _, original in D.Items(plan, "builds") do
		local entry = original
		for _, target in D.Items(receipt, "targets") do
			if
				D.Equal(D.Get(target, "name"), D.Get(entry, "name"))
				and D.Equal(D.Get(target, "source_sha"), D.Get(entry, "source_sha"))
			then
				entry = D.Set(
					entry,
					"accepted",
					C.Object({
						release_id = D.Required(release, "id"),
						asset_id = D.Required(archive, "id"),
						archive_sha256 = D.Required(receipt, "bundle_sha256"),
						source_sha = D.Required(target, "source_sha"),
						resolved_fingerprint = D.Required(target, "resolved_fingerprint"),
						artifact = D.Required(target, "artifact"),
						envelope = C.Hash(envelope),
					})
				)
			end
		end
		table.insert(builds, entry)
	end
	D.Write("build/receipts/accepted-plan.json", D.Set(plan, "builds", C.Array(builds)))
end

function Receipts.Run()
	local args = Process.args
	local operation = args[1]
	if operation == "authorize" then
		Receipts.Authorize()
	elseif operation == "plan" then
		Receipts.Plan()
	elseif operation == "execution" then
		Receipts.Execution()
	elseif operation == "collect" then
		storeCollection(args)
	elseif operation == "keygen" then
		outsideExecution()
		local path = assert(args[2], "new external private-key path required")
		local public = Native.Call("keygen", { path = path, workspace = Process.cwd })
		assert(type(public) == "string", "invalid native public key")
		if Process.os == "windows" then
			local account = Commands.Run("whoami", {}):gsub("%s+$", "")
			Commands.Run("icacls", { path, "/inheritance:r", "/grant:r", account .. ":F" })
		end
		Stdio.write(assert(C.Encode(C.Object({
			id = Native.UUID(),
			algorithm = "ed25519",
			login = GitHub.Actor(),
			public_key = public,
			revoked = false,
		}))) .. "\n")
	elseif operation == "collect-act" then
		Collection.Clean()
		local store = args[2] or "build/cache/act-artifacts/1"
		local extracted = "build/tmp/receipts/act/" .. Native.UUID()
		local function extract(name: string, destination: string)
			local directory = store .. "/" .. Shape.Relative(name)
			local archives: { string } = {}
			for _, file in Fs.readDir(directory) do
				if file:match("%.zip$") then
					table.insert(archives, file)
				end
			end
			assert(#archives == 1, "expected exactly one artifact archive")
			local archive = directory .. "/" .. archives[1]
			local windows = Process.os == "windows"
			local program = if windows then "tar" else "unzip"
			for path in
				Commands.Run(program, if windows then { "-tf", archive } else { "-Z1", archive }):gmatch("[^\r\n]+")
			do
				Shape.Relative((path:gsub("/$", "")))
			end
			for line in
				Commands.Run(program, if windows then { "-tvf", archive } else { "-Z", "-l", archive })
					:gmatch("[^\r\n]+")
			do
				assert(
					not line:match("^[lbcps][rwx%-][rwx%-][rwx%-]"),
					"artifact archive contains links or special files"
				)
			end
			assert(not Fs.metadata(destination).exists, "artifact destination must be fresh")
			Fs.writeDir(destination)
			Commands.Run(
				program,
				if windows then { "-xf", archive, "-C", destination } else { "-q", archive, "-d", destination }
			)
			Bundles.Manifest(destination)
		end
		extract("release-plan", extracted .. "/plan")
		local planFile = extracted .. "/plan/plan.json"
		local plan = D.Read(planFile)
		assert(
			D.Get(plan, "controller_sha") == Git.Text({ "rev-parse", "HEAD" })
				and D.Get(D.Required(plan, "context"), "local") == true,
			"act store differs from local checkout"
		)
		for _, entry in D.Items(plan, "builds") do
			local name = Shape.Relative(D.Text(entry, "artifact"))
			if not Fs.isDir(store .. "/" .. name) then
				continue
			end
			extract(name, extracted .. "/distributions/" .. name)
			local log = "build-logs-" .. D.Text(entry, "source_sha") .. "-" .. Shape.Relative(D.Text(entry, "name"))
			extract(log, extracted .. "/logs/" .. log)
		end
		storeCollection({
			"collect",
			planFile,
			extracted .. "/distributions",
			extracted .. "/logs",
			args[3] or "build/receipts",
		})
	elseif operation == "report" then
		Receipts.Report()
	elseif operation == "accepted-check" then
		local envelope = D.Read("build/receipts/receipt.json")
		local receipt = D.Required(envelope, "receipt")
		Hosted.FreshPR(receipt)
		if D.Get(receipt, "diagnostic") == true then
			return
		end
		assert(
			table.find({ "workflow_dispatch", "push" }, Process.env.GITHUB_EVENT_NAME or "")
				and (Process.env.GITHUB_REF == "refs/heads/source" or D.Get(
					D.Required(envelope, "authentication"),
					"bootstrap"
				) == true)
				and GitHub.IsAdmin(GitHub.Actor()),
			"trusted admin source workflow required"
		)
		Hosted.SetCheck(
			D.Text(D.Required(receipt, "pr"), "head_sha"),
			"success",
			"Independent admin validation completed; receipt retained in validation-receipt artifact."
		)
	elseif operation == "verify-pr" then
		local plan = D.Read("build/tmp/releases/plan.json")
		local before = D.Required(D.Required(plan, "context"), "pr")
		local pr = Hosted.CurrentPR(D.Number(before, "number"))
		assert(D.Equal(pr, before), "PR changed")
		local accepted = Hosted.Discover(plan, pr).Accepted
		local complete = #accepted == #D.Items(plan, "builds")
		Hosted.SetCheck(
			D.Text(pr, "head_sha"),
			if complete then "success" else "failure",
			if complete
				then "Verified current accepted receipts for all targets."
				else "Independent admin validation required."
		)
		assert(complete, "waiting for independent admin validation")
	elseif operation == "check-ready" then
		local plan = D.Read("build/tmp/releases/plan.json")
		local context = D.Required(plan, "context")
		if D.Get(context, "local") ~= true and D.Get(context, "requested") ~= true then
			for _, entry in D.Items(plan, "builds") do
				assert(D.Get(entry, "accepted"), "admin validation required; no automatic hosted fallback")
			end
		end
	elseif operation == "local-context" or operation == "claim-context" then
		Collection.Clean()
		local pr = Hosted.CurrentPR(assert(tonumber(args[2])))
		local head = Git.Text({ "rev-parse", "HEAD" })
		if operation == "claim-context" then
			assert(D.Get(pr, "head_sha") == head, "contributor checkout must match PR head")
		else
			local source = D.Required(assert(api().Request("/git/ref/heads/source")), "object")
			local bootstrap = table.find(args, "--bootstrap")
				and head == D.Text(pr, "head_sha")
				and GitHub.IsAdmin(GitHub.Actor())
				and Hosted.PredatesContract(D.Text(pr, "base_sha"))
			assert(head == D.Text(source, "sha") or bootstrap, "local validation requires clean source controller")
			fetch(D.Text(pr, "head_sha"), (Commands.Run("gh", { "auth", "token" }):gsub("%s+$", "")))
		end
		D.Write(
			args[3] or "build/tmp/receipts/event.json",
			C.Object({
				inputs = C.Object({ operation = "Build", pull_request = "#" .. D.Number(pr, "number") }),
				receipt_context = pr,
			})
		)
	elseif operation == "sign" or operation == "submit" or operation == "claim-submit" then
		outsideExecution()
		local file = assert(args[2], "receipt path required")
		local envelope = D.Read(file)
		local receipt = Verification.Validate(D.Required(envelope, "receipt"))
		Hosted.FreshPR(receipt)
		if operation == "claim-submit" then
			assert(D.Number(D.Required(receipt, "pr"), "number") > 0, "claim requires open PR")
			local body = "Local CI claim; requires independent admin validation.\n\n```json\n"
				.. assert(C.Encode(C.Object({ receipt = receipt, authentication = C.Object({ kind = "claim" }) })))
				.. "\n```"
			assert(#body <= 60000, "claim exceeds comment size limit")
			api().JSON(
				"POST",
				"/issues/" .. D.Number(D.Required(receipt, "pr"), "number") .. "/comments",
				C.Object({ body = body })
			)
		else
			assert(GitHub.IsAdmin(GitHub.Actor()), "administrator validator required")
			local archive = parent(file) .. "/bundle.tar.gz"
			assert(
				Serde.hash("sha256", Fs.readFile(archive)) == D.Text(receipt, "bundle_sha256"),
				"bundle checksum mismatch"
			)
			if operation == "sign" then
				local keyPath = assert(args[4], "external private key required")
				local workspace = Process.cwd:gsub("\\", "/"):gsub("/$", "")
				local normalized = keyPath:gsub("\\", "/")
				assert(normalized:match("^%a:/") or normalized:sub(1, 1) == "/", "absolute private key path required")
				assert(
					normalized:lower() ~= workspace:lower()
						and normalized:sub(1, #workspace + 1):lower() ~= (workspace .. "/"):lower(),
					"signing key must live outside repository"
				)
				Collection.VerifyBundle(parent(file) .. "/bundle", receipt)
				if args[5] then
					receipt = D.Set(
						receipt,
						"comparison",
						C.Array(Verification.Compare(D.Required(D.Read(args[5]), "receipt"), receipt))
					)
				end
				local key = Native.Call("keyfile", { path = keyPath, workspace = Process.cwd })
				assert(type(key) == "string", "invalid private key response")
				D.Write(file, Authentication.Sign(receipt, assert(args[3], "enrolled key ID required"), key))
			else
				assert(
					D.Get(D.Required(envelope, "authentication"), "kind") == "signature",
					"local staging requires enrolled signature"
				)
				Hosted.VerifyEnvelope(envelope)
				Hosted.Upload(envelope, archive)
			end
		end
	elseif operation == "merge" then
		Collection.Clean()
		assert(GitHub.IsAdmin(GitHub.Actor()), "administrator required")
		local number = assert(tonumber(args[2]))
		local pr = Hosted.CurrentPR(number)
		local source = D.Required(assert(api().Request("/git/ref/heads/source")), "object")
		local head = Git.Text({ "rev-parse", "HEAD" })
		assert(
			head == D.Text(source, "sha")
				or (head == D.Text(pr, "head_sha") and Hosted.PredatesContract(D.Text(pr, "base_sha"))),
			"merge requires trusted controller checkout"
		)
		fetch(D.Text(pr, "head_sha"), (Commands.Run("gh", { "auth", "token" }):gsub("%s+$", "")))
		Git.Bytes({ "merge-base", "--is-ancestor", D.Text(pr, "base_sha"), D.Text(pr, "head_sha") })
		local previous = {
			ACT = Process.env.ACT,
			CI_TESTED_SHA = Process.env.CI_TESTED_SHA,
			CI_RECEIPT_PR = Process.env.CI_RECEIPT_PR,
		}
		Process.env.ACT = "true"
		Process.env.CI_TESTED_SHA = D.Text(pr, "head_sha")
		Process.env.CI_RECEIPT_PR = tostring(number)
		local ok, failure = pcall(Resolve.Run)
		Process.env.ACT = previous.ACT
		Process.env.CI_TESTED_SHA = previous.CI_TESTED_SHA
		Process.env.CI_RECEIPT_PR = previous.CI_RECEIPT_PR
		assert(ok, tostring(failure))
		local plan = D.Read("build/tmp/releases/plan.json")
		assert(
			#Hosted.Discover(plan, pr).Accepted == #D.Items(plan, "builds"),
			"all targets require accepted admin validation"
		)
		assert(D.Equal(pr, Hosted.CurrentPR(number)), "PR changed during verification")
		Commands.Run("gh", {
			"pr",
			"merge",
			tostring(number),
			"--repo",
			GitHub.Repository(),
			"--merge",
			"--match-head-commit",
			D.Text(pr, "head_sha"),
		})
	elseif operation == "request" then
		assert(
			Process.env.ACT ~= "true" and GitHub.IsAdmin(GitHub.Actor()),
			"request validation outside act as administrator"
		)
		local number = tonumber(args[2] or "0") or 0
		local bootstrap = table.find(args, "--bootstrap") ~= nil
		local pr = if number > 0 then Hosted.CurrentPR(number) else nil
		assert(
			not bootstrap
				or (
					pr
					and D.Get(pr, "head_sha") == Git.Text({ "rev-parse", "HEAD" })
					and Hosted.PredatesContract(D.Text(pr, "base_sha"))
				),
			"bootstrap requires exact first activation PR"
		)
		assert(not args[3] or args[3]:sub(1, 2) == "--", "receipt JSON is not a workflow input")
		local selected = if pr then assert(api().Request("/pulls/" .. number)) else nil
		local label = if selected
			then Request.PullRequestLabel({ number = D.Number(selected, "number"), title = D.Text(selected, "title") })
			else "Source"
		api().Request("/actions/workflows/ci.yml/dispatches", {
			Method = "POST",
			Body = assert(C.Encode(C.Object({
				ref = if bootstrap then Git.Text({ "branch", "--show-current" }) else "source",
				inputs = C.Object({ operation = "Build", pull_request = label }),
			}))),
		})
	else
		error("unknown receipt operation: " .. tostring(operation))
	end
end

return Receipts
