-- security/receipts/tests/bundles.luau
--!strict

local Test = require("@testing")

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Datetime = require("@lune/datetime")
local Process = require("@lune/process")
local C = require("../../../libraries/bootstrap/canonical")
local D = require("../../../libraries/bootstrap/documents")
local Bundles = require("../../../libraries/bootstrap/bundles")
local Commands = require("../../../libraries/bootstrap/commands")
local Files = require("../../../libraries/bootstrap/files")
local Base64 = require("../../../libraries/bootstrap/base64")
local GitHub = require("../../../libraries/bootstrap/github")
local Client = require("../../../publication/releases/client")
local Distributions = require("../../../publication/releases/distributions")
local Releases = require("../../../publication/releases/cli")
local Authentication = require("../authentication")
local Collection = require("../collection")
local Hosted = require("../hosted")

--# Helpers

local function tar(name: string, kind: string): string
	local header = buffer.create(512)
	local function write(offset: number, text: string)
		buffer.writestring(header, offset, text)
	end
	write(0, name)
	write(100, "0000644\0")
	write(108, "0000000\0")
	write(116, "0000000\0")
	write(124, "00000000000\0")
	write(136, "00000000000\0")
	write(148, "        ")
	write(156, kind)
	write(157, "../outside")
	write(257, "ustar\0")
	write(263, "00")
	local checksum = 0
	for index = 0, 511 do
		checksum += buffer.readu8(header, index)
	end
	write(148, string.format("%06o\0 ", checksum))
	return Serde.compress("gzip", buffer.tostring(header) .. string.rep("\0", 1024))
end

local function reuse(): boolean
	local root = "build/tests/receipt-reuse"
	Files.Reset(root)
	local tested, selected = string.rep("a", 40), string.rep("b", 40)
	local fingerprint, controller, tree, manifestHash =
		string.rep("c", 64), string.rep("d", 64), string.rep("e", 40), string.rep("f", 64)
	local artifact, logName = "distribution-tested-linux-x64", "build-logs-tested-linux-x64"
	local distribution = root .. "/distributions/" .. artifact
	local logs = root .. "/logs/" .. logName
	Fs.writeDir(distribution)
	Fs.writeDir(logs)
	Fs.writeFile(logs .. "/probe-1.log", "actual toolchain probe")
	local logFiles = Bundles.Manifest(logs)
	local execution = C.Object({ kind = "native", os = "linux", arch = "x64", probe_logs = logFiles })
	local resolved = C.Hash(C.Object({ inputs = fingerprint, execution = execution }))
	local metadata = C.Object({

		source_sha = tested,
		tree = tree,
		source_manifest_sha256 = manifestHash,
		fingerprint = fingerprint,
		target = "linux-x64",
		execution = execution,
		resolved_fingerprint = resolved,
	})
	D.Write(distribution .. "/provenance.json", metadata)
	Fs.writeFile(distribution .. "/distribution.tar.gz", "packaged payload")
	D.Write(distribution .. "/manifest.json", Bundles.Manifest(distribution))
	local target = C.Object({
		name = "linux-x64",
		source_sha = tested,
		tree = tree,
		source_manifest_sha256 = manifestHash,
		fingerprint = fingerprint,
		reuse_identity = "source_tree",
		resolved_fingerprint = resolved,
		result = "success",
		execution = execution,
		files = Bundles.Manifest(distribution),
		logs = logFiles,
		artifact = artifact,
		log_artifact = logName,
	})
	local receipt = C.Object({

		repository = "owner/project",
		tested_sha = tested,
		tree = tree,
		source_manifest_sha256 = manifestHash,
		controller_hash = controller,
		controller_sha = tested,
		created_at = Datetime.now():toIsoDate(),
		pr = C.Object({ number = 0, head_sha = tested, base_sha = tested }),
		targets = C.Array({ target }),
	})
	Collection.Bundle(root .. "/bundle", receipt, root .. "/distributions", root .. "/logs")
	Commands.Run("tar", { "-czf", root .. "/bundle.tar.gz", "-C", root .. "/bundle", "." })
	local archiveBytes = Fs.readFile(root .. "/bundle.tar.gz")
	receipt = D.Set(receipt, "bundle_sha256", Serde.hash("sha256", archiveBytes))
	Collection.VerifyBundle(root .. "/bundle", receipt)
	local keys = D.Required(D.Required(D.Read("security/receipts/ruleset.json"), "cases"), "test_key")
	local envelope = Authentication.Sign(receipt, "admin-key", D.Text(keys, "private_key"))
	local envelopeBytes = assert(C.Encode(envelope))
	local enrollment = C.Object({
		id = "admin-key",
		algorithm = "ed25519",
		public_key = D.Required(keys, "public_key"),
		login = "admin",
		revoked = false,
	})
	local release = C.Object({
		id = 1,
		draft = true,
		tag_name = "ci-validation-fixture",
		assets = C.Array({
			C.Object({
				id = 2,
				name = "receipt.json",
				size = #envelopeBytes,
				digest = "sha256:" .. Serde.hash("sha256", envelopeBytes),
			}),
			C.Object({
				id = 3,
				name = "bundle.tar.gz",
				size = #archiveBytes,
				digest = "sha256:" .. Serde.hash("sha256", archiveBytes),
			}),
		}),
	})
	local fake: Client.API = {
		Request = function(route)
			if route:match("^/contents/security/receipts/keys.json") then
				return C.Object({
					content = Base64.Encode(assert(C.Encode(C.Object({ keys = C.Array({ enrollment }) })))),
				})
			elseif route == "/releases/1" then
				return release
			end
			error("unexpected fake request: " .. route)
		end,
		JSON = function()
			error("receipt reuse must not mutate GitHub")
		end,
		Pages = function(route)
			assert(route == "/releases")
			return { release }
		end,
		Bytes = function(route)
			if route == "/releases/assets/2" then
				return envelopeBytes
			elseif route == "/releases/assets/3" then
				return archiveBytes
			end
			error("unexpected fake download")
		end,
	}
	local previousClient, previousAdmin, previousRepository = Client.new, GitHub.IsAdmin, Process.env.GITHUB_REPOSITORY
	Client.new = function()
		return fake
	end
	GitHub.IsAdmin = function(login)
		return login == "admin"
	end
	Process.env.GITHUB_REPOSITORY = "owner/project"
	local ok, failure = pcall(function()
		local selectedEntry = D.Set(
			D.Set(D.Set(D.Set(target, "source_sha", selected), "runner", "ubuntu-latest"), "platform", "linux/amd64"),
			"artifact",
			"distribution-selected-linux-x64"
		)
		local plan = C.Object({ controller_hash = controller, builds = C.Array({ selectedEntry }) })
		local discovery = Hosted.Discover(plan, nil, true)
		assert(#discovery.Accepted == 1, table.concat(discovery.Rejected, "\n"))
		local accepted = D.Items(discovery.Plan, "builds")[1]
		local previousSpec, previousOutput = Process.env.CI_BUILD_SPEC, Process.env.GITHUB_OUTPUT
		Process.env.CI_BUILD_SPEC = assert(C.Encode(accepted))
		Process.env.GITHUB_OUTPUT = ""
		local prepared, preparationFailure = pcall(Releases.Prepare)
		Process.env.CI_BUILD_SPEC = previousSpec
		Process.env.GITHUB_OUTPUT = previousOutput
		assert(prepared, tostring(preparationFailure))
		assert(D.Get(Distributions.Verify("build/artifacts", accepted).metadata, "source_sha") == tested)
		local destination = root .. "/restored"
		Hosted.Restore(accepted, destination)
		assert(D.Get(Distributions.Verify(destination, accepted).metadata, "source_sha") == tested)
		assert(not Fs.isDir("build/tmp/source/" .. selected), "reuse must not prepare a compiler checkout")
		enrollment = D.Set(enrollment, "revoked", true)
		assert(#Hosted.Discover(plan).Accepted == 0, "revoked key must not grant reuse")
	end)
	Client.new = previousClient
	GitHub.IsAdmin = previousAdmin
	Process.env.GITHUB_REPOSITORY = previousRepository
	assert(ok, tostring(failure))
	return true
end

local function execute(kind: string): boolean
	if kind == "signed-reuse" then
		return reuse()
	end
	local root = "build/tests/bundle-safety"
	Files.Reset(root)
	if kind == "manifest" then
		Fs.writeFile(root .. "/file.txt", "original")
		local expected = Bundles.Manifest(root)
		Bundles.VerifyFiles(root, expected)
		Fs.writeFile(root .. "/file.txt", "changed")
		assert(not pcall(Bundles.VerifyFiles, root, expected))
		Fs.writeFile(root .. "/file.txt", "original")
		Fs.writeFile(root .. "/extra.txt", "extra")
		assert(not pcall(Bundles.VerifyFiles, root, expected))
		return true
	end
	local archive = root .. "/input.tar.gz"
	Fs.writeFile(
		archive,
		tar(
			if kind == "traversal" then "../escape" else "file.txt",
			if kind == "symlink" then "2" elseif kind == "special" then "6" else "0"
		)
	)
	local destination = root .. "/extracted"
	if kind == "existing" then
		Fs.writeDir(destination)
	end
	local ok = pcall(Bundles.Unpack, archive, destination)
	assert(ok == (kind == "ordinary"), "unexpected archive safety result")
	return true
end

local function cases(): { Test.Case<string, boolean> }
	local result: { Test.Case<string, boolean> } = {}
	for _, kind in { "manifest", "ordinary", "existing", "traversal", "symlink", "special", "signed-reuse" } do
		table.insert(result, { Name = kind, Input = kind, Expected = true })
	end
	return result
end

--# Declaration

local definition: Test.Definition<string, boolean> =
	{ Name = "Receipt bundle safety and signed reuse", Execute = execute, Cases = cases() }

return Test.new(definition)
