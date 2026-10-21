-- ci/fabricator/distribution/images/build.luau
--!strict

local Images = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Config = require("../../../libraries/registry/config")
local Catalogue = require("../../../libraries/registry/catalogue")

--# Types

type ProbeResult = { argv: { string }, stdout: string, stderr: string }

--# Helpers

local function execute(arguments: { string })
	local result = Process.exec("docker", arguments, { stdio = "inherit" })

	assert(result.ok, "Docker image operation failed")
end

local function exportRecipes(): string
	local ref = Process.env.CI_INPUT_REF

	if not ref or ref == "" or (Process.env.ACT == "true" and ref == Process.env.CI_TESTED_SHA) then
		return "ci/fabricator/distribution/images"
	end

	local root = "build/tmp/image-input/" .. ref
	local recipes = "ci/fabricator/distribution/images"

	Fs.writeDir(root)

	local archive =
		Process.exec("git", { "archive", "--format=tar", "--output=build/tmp/image-source.tar", ref, recipes })

	assert(archive.ok, "cannot export selected image recipes")

	local extracted = Process.exec("tar", { "-xf", "build/tmp/image-source.tar", "-C", root })

	assert(extracted.ok, "cannot extract selected image recipes")

	return root .. "/" .. recipes
end

local function buildLayers(image: Catalogue.Image, root: string, tag: string, baseTag: string)
	execute({
		"build",
		"--platform",
		image.platform,
		"--file",
		root .. "/" .. image.recipe,
		"--build-arg",
		"BASE_IMAGE=" .. image.base,
		"--build-arg",
		"PACKAGES=" .. table.concat(image.common_packages, " "),
		"--tag",
		baseTag,
		root,
	})

	local source = (Process.env.GITHUB_SERVER_URL or "https://github.com")
		.. "/"
		.. (Process.env.GITHUB_REPOSITORY or "")

	execute({
		"build",
		"--platform",
		image.platform,
		"--file",
		root .. "/toolchains/" .. image.profile .. "/Dockerfile",
		"--build-arg",
		"BASE_IMAGE=" .. baseTag,
		"--build-arg",
		"PACKAGES=" .. table.concat(image.packages, " "),
		"--label",
		"org.opencontainers.image.source=" .. source,
		"--label",
		"org.opencontainers.image.revision=" .. (Process.env.GITHUB_SHA or ""),
		"--tag",
		tag,
		root,
	})
end

local function recordInventory(image: Catalogue.Image, tag: string, output: string)
	local arguments = { "run", "--rm", "--platform", image.platform, tag }

	for _, argument in ipairs(image.inventory) do
		table.insert(arguments, argument)
	end

	local inventory = Process.exec("docker", arguments)

	assert(inventory.ok, "could not record installed package versions")

	Fs.writeFile(output .. "/versions.txt", inventory.stdout)
end

local function runProbes(image: Catalogue.Image, tag: string): { ProbeResult }
	local results = {}

	for _, probe in ipairs(image.probes) do
		local arguments = { "run", "--rm", "--platform", image.platform, tag }

		for _, argument in ipairs(probe.argv) do
			table.insert(arguments, argument)
		end

		local result = Process.exec("docker", arguments)

		assert(result.code == probe.code, "image toolchain probe failed")

		table.insert(results, { argv = probe.argv, stdout = result.stdout, stderr = result.stderr })
	end

	return results
end

local function exportImage(image: Catalogue.Image, tag: string, output: string, probes: { ProbeResult })
	local inspection = Process.exec("docker", { "image", "inspect", tag, "--format", "{{json .}}" })

	assert(inspection.ok, "cannot inspect exported image identity")

	-- Docker is the external boundary; only these identity fields are consumed.
	local inspected = Serde.decode("json", inspection.stdout) :: { Id: string, Os: string, Architecture: string }

	assert(inspected.Os .. "/" .. inspected.Architecture == image.platform, "exported image platform mismatch")

	local record = {
		name = image.name,
		id = inspected.Id,
		os = inspected.Os,
		architecture = inspected.Architecture,
		tag = tag,
		platform = image.platform,
		base = image.base,
		profile = image.profile,
		version = image.version,
		probes = probes,
	}

	Fs.writeFile(output .. "/image.json", Serde.encode("json", record, true))
	execute({ "save", "--output", output .. "/image.tar", tag })
end

--# Functions

function Images.Run()
	local config = Config.Read()
	local name = Process.args[1]

	assert(name ~= nil, "missing image name")

	local image = Catalogue.Image(name)

	assert(config.images.enabled and table.find(config.images.names, image.name), "image generation is not selected")

	local identity = Process.env.CI_IMAGE_ID or "generated"

	assert(identity:match("^[a-z0-9%-]+$"), "invalid image identity")

	local root = exportRecipes()
	local output = "build/images/" .. image.name
	local tag = "template-ci/" .. image.name .. ":" .. identity
	local baseTag = "template-ci/base-" .. image.name .. ":" .. identity

	Fs.writeDir(output)
	buildLayers(image, root, tag, baseTag)
	recordInventory(image, tag, output)

	local probes = runProbes(image, tag)

	exportImage(image, tag, output, probes)
end

return Images
