-- security/receipts/identity.luau
--!strict

local Identity = {}

--# Modules

local Git = require("../../libraries/bootstrap/git")
local Config = require("../../libraries/registry/config")
local Canonical = require("../../libraries/bootstrap/canonical")
local Serde = require("@lune/serde")

--# Types

export type File = { path: string, mode: string, sha256: string }
export type Snapshot = { source_sha: string, tree: string, source_manifest_sha256: string, files: { File } }

--# Functions

function Identity.Read(sha: string, cwd: string?): Snapshot
	Git.FullSHA(sha)
	local files: { File } = {}
	local values: { Canonical.Value } = {}
	local objects = {}
	local entries = {}

	for _, line in Git.Bytes({ "ls-tree", "-r", "-z", sha }, cwd):split("\0") do
		if line == "" then
			continue
		end

		local mode, kind, oid, path = line:match("^(%d+) (%w+) ([a-f0-9]+)\t(.*)$")
		assert(mode and kind and oid and path, "invalid tracked input record")
		Config.Relative(path)
		assert(kind == "blob", "Submodules require explicit immutable input support")
		table.insert(objects, oid)
		table.insert(entries, { path = path, mode = mode })
	end

	local blobs = Git.Blobs(objects, cwd)

	for index, entry in entries do
		local path, mode = entry.path, entry.mode
		local digest = Serde.hash("sha256", blobs[index])
		local file = { path = path, mode = mode, sha256 = digest }
		table.insert(files, file)
		table.insert(values, Canonical.Object({ path = path, mode = mode, sha256 = digest }))
	end

	return {
		source_sha = sha,
		tree = Git.Text({ "rev-parse", sha .. "^{tree}" }, cwd),
		source_manifest_sha256 = Canonical.Hash(Canonical.Array(values)),
		files = files,
	}
end

return Identity
