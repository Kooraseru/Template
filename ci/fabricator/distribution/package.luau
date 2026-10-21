-- fabricator/distribution/package.luau
--!strict

local Package = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Process = require("@lune/process")
local Config = require("../../libraries/registry/config")
local Files = require("../../libraries/bootstrap/files")

--# Types

type ManifestEntry = { path: string, sha256: string }

--# Constants

local OUTPUT_ROOT = "build/artifacts"

--# Helpers

local function copyOutputs(paths: { string })
	for _, path in ipairs(paths) do
		assert(Fs.isFile(path) or Fs.isDir(path), "missing configured package output: " .. path)
		assert(
			path ~= OUTPUT_ROOT and path:sub(1, #OUTPUT_ROOT + 1) ~= OUTPUT_ROOT .. "/",
			"package cannot copy itself"
		)

		local destination = OUTPUT_ROOT .. "/" .. path:sub(7)

		Files.Copy(path, destination)
	end
end

local function archiveOutputs()
	local result = Process.exec("tar", { "-czf", "build/distribution.tar.gz", "-C", OUTPUT_ROOT, "." })

	assert(result.ok, "package archive failed: " .. result.stderr)

	Files.Copy("build/distribution.tar.gz", OUTPUT_ROOT .. "/distribution.tar.gz")
end

local function copyProvenance(spec: Config.BuildSpec)
	local provenance = Fs.readFile("build/tmp/releases/execution.json")
	local metadata = Serde.decode("json", provenance) :: { source_sha: string, fingerprint: string }

	assert(
		metadata.source_sha == spec.source_sha and metadata.fingerprint == spec.fingerprint,
		"execution provenance does not match the package target"
	)

	-- Keep the accepted bytes: re-encoding empty arrays through Luau changes them.
	Fs.writeFile(OUTPUT_ROOT .. "/provenance.json", provenance)
end

local function inspect(directory: string, prefix: string, manifest: { ManifestEntry })
	for _, name in ipairs(Fs.readDir(directory)) do
		local input = directory .. "/" .. name
		local relative = prefix .. name

		if Fs.isDir(input) then
			inspect(input, relative .. "/", manifest)
		else
			local contents = Fs.readFile(input)

			table.insert(manifest, { path = relative, sha256 = Serde.hash("sha256", contents) })
		end
	end
end

--# Functions

function Package.Run()
	local config = Config.Read()
	local spec: Config.BuildSpec? = nil

	if Process.env.CI_BUILD_SPEC then
		spec = Serde.decode("json", Process.env.CI_BUILD_SPEC) :: Config.BuildSpec
		config.build = spec.build
	end

	Files.Reset(OUTPUT_ROOT)
	copyOutputs(config.build.package_paths)
	archiveOutputs()

	if spec then
		copyProvenance(spec)
	end

	local manifest: { ManifestEntry } = {}

	inspect(OUTPUT_ROOT, "", manifest)

	Fs.writeFile(OUTPUT_ROOT .. "/manifest.json", Serde.encode("json", manifest, true))
end

return Package
