--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local config = require("../lib/config").read()
local catalogue = require("../lib/catalogue")
local name = assert(process.args[1], "missing image name")
local image = catalogue.image(name)
local inputRoot = "ci/images"
local ref = process.env.CI_INPUT_REF
if ref and ref ~= "" then
    inputRoot = "build/tmp/image-input/" .. ref
    fs.writeDir(inputRoot)
    local archive = process.exec("git", { "archive", "--format=tar", "--output=build/tmp/image-source.tar", ref, "ci/images" })
    assert(archive.ok, "cannot export selected image recipes")
    local extracted = process.exec("tar", { "-xf", "build/tmp/image-source.tar", "-C", inputRoot })
    assert(extracted.ok, "cannot extract selected image recipes")
    inputRoot ..= "/ci/images"
end
assert(
    config.images.enabled and table.find(config.images.names, image.name),
    "image generation is not selected"
)
local output = "build/images/" .. image.name
fs.writeDir(output)

local function execute(arguments: { string })
    local result = process.exec("docker", arguments, { stdio = "inherit" })
    assert(result.ok, "Docker image operation failed")
end
local identity = process.env.CI_IMAGE_ID or "generated"
assert(identity:match("^[a-z0-9%-]+$"), "invalid image identity")
local baseTag = "template-ci/base-" .. image.name .. ":" .. identity
local tag = "template-ci/" .. image.name .. ":" .. identity
execute({
    "build",
    "--platform",
    image.platform,
    "--file",
    inputRoot .. "/" .. image.recipe,
    "--build-arg",
    "BASE_IMAGE=" .. image.base,
    "--build-arg",
    "PACKAGES=" .. table.concat(image.common_packages, " "),
    "--tag",
    baseTag,
    inputRoot,
})
execute({
    "build",
    "--platform",
    image.platform,
    "--file",
    inputRoot .. "/toolchains/" .. image.profile .. "/Dockerfile",
    "--build-arg",
    "BASE_IMAGE=" .. baseTag,
    "--build-arg",
    "PACKAGES=" .. table.concat(image.packages, " "),
    "--label",
    "org.opencontainers.image.source="
        .. (process.env.GITHUB_SERVER_URL or "https://github.com")
        .. "/"
        .. (process.env.GITHUB_REPOSITORY or ""),
    "--label",
    "org.opencontainers.image.revision=" .. (process.env.GITHUB_SHA or ""),
    "--tag",
    tag,
    inputRoot,
})
local inventoryArguments = { "run", "--rm", "--platform", image.platform, tag }
for _, argument in image.inventory do
    table.insert(inventoryArguments, argument)
end
local inventory = process.exec("docker", inventoryArguments)
assert(inventory.ok, "could not record installed package versions")
fs.writeFile(output .. "/versions.txt", inventory.stdout)
local probeResults = {}
for _, probe in image.probes do
    local arguments = { "run", "--rm", "--platform", image.platform, tag }
    for _, argument in probe.argv do
        table.insert(arguments, argument)
    end
    local result = process.exec("docker", arguments)
    assert(result.code == probe.code, "image toolchain probe failed")
    table.insert(
        probeResults,
        { argv = probe.argv, stdout = result.stdout, stderr = result.stderr }
    )
end
local inspect = process.exec("docker", { "image", "inspect", tag, "--format", "{{json .}}" })
assert(inspect.ok, "cannot inspect exported image identity")
local inspected = serde.decode("json", inspect.stdout)
assert(inspected.Os .. "/" .. inspected.Architecture == image.platform, "exported image platform mismatch")
fs.writeFile(
    output .. "/image.json",
    serde.encode("json", {
        name = image.name,
        id = inspected.Id,
        os = inspected.Os,
        architecture = inspected.Architecture,
        tag = tag,
        platform = image.platform,
        base = image.base,
        profile = image.profile,
        version = image.version,
        probes = probeResults,
    }, true)
)
execute({ "save", "--output", output .. "/image.tar", tag })
