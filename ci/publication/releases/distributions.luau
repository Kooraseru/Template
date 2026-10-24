-- ci/publication/releases/distributions.luau
--!strict

local Distributions = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local D = require("../../utilities/documents")
local C = require("../../utilities/canonical")
local Json = require("../../utilities/json")
local Bundles = require("../../utilities/bundles")

--# Functions

function Distributions.Verify(root: string, expected: C.Value): { metadata: C.Value, manifest: C.Value }
	local metadata = D.Read(root .. "/provenance.json")
	assert(D.Get(metadata, "schema") == nil, "provenance contains unsupported schema field")
	local accepted = D.Get(expected, "accepted")
	local source = if accepted
		then D.Required(accepted, "source_sha")
		else D.Get(expected, "accepted_source_sha") or D.Required(expected, "source_sha")
	assert(
		D.Equal(D.Get(metadata, "source_sha"), source)
			and D.Equal(D.Get(metadata, "fingerprint"), D.Get(expected, "fingerprint"))
			and D.Equal(D.Get(metadata, "target"), D.Get(expected, "name")),
		"distribution provenance mismatch"
	)
	if accepted and D.Get(accepted, "resolved_fingerprint") then
		assert(
			D.Equal(D.Get(metadata, "resolved_fingerprint"), D.Get(accepted, "resolved_fingerprint")),
			"resolved build environment mismatch"
		)
	end
	local manifest = D.Read(root .. "/manifest.json")
	local provenance, archive = false, false
	for _, file in Json.Array(manifest) do
		local path = D.Text(file, "path")
		provenance = provenance or path == "provenance.json"
		archive = archive or path == "distribution.tar.gz"
		local digest = D.Text(file, "sha256")
		assert(#digest == 64 and digest:match("^[a-f0-9]+$"), "invalid distribution manifest digest")
	end
	assert(provenance and archive, "incomplete distribution manifest")
	local files = table.clone(Json.Array(manifest))
	table.insert(
		files,
		C.Object({
			path = "manifest.json",
			sha256 = Serde.hash("sha256", Fs.readFile(root .. "/manifest.json")),
		})
	)
	Bundles.VerifyFiles(root, C.Array(files))
	return { metadata = metadata, manifest = manifest }
end

return Distributions
