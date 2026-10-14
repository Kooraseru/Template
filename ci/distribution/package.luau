--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local config = require("../lib/config").read()
local files = require("../lib/files")
local spec = if process.env.CI_BUILD_SPEC then serde.decode("json", process.env.CI_BUILD_SPEC) else nil
if spec then config.build = spec.build end
files.reset("build/artifacts")
local manifest = {}
for _, path in config.build.package_paths do
    assert(fs.isFile(path) or fs.isDir(path), "missing configured package output: " .. path)
    assert(
        path ~= "build/artifacts" and path:sub(1, 16) ~= "build/artifacts/",
        "package cannot copy itself"
    )
    local destination = "build/artifacts/" .. path:sub(7)
    files.copy(path, destination)
end
local archive =
    process.exec("tar", { "-czf", "build/distribution.tar.gz", "-C", "build/artifacts", "." })
assert(archive.ok, "package archive failed: " .. archive.stderr)
files.copy("build/distribution.tar.gz", "build/artifacts/distribution.tar.gz")
if spec then
    fs.writeFile("build/artifacts/provenance.json", serde.encode("json", {
        schema = 1, source_sha = spec.source_sha, fingerprint = spec.fingerprint,
        target = spec.name, controller_sha = process.env.GITHUB_SHA or "local",
    }, true))
end
local function inspect(path: string, prefix: string)
    for _, name in fs.readDir(path) do
        local input = path .. "/" .. name
        local relative = prefix .. name
        if fs.isDir(input) then
            inspect(input, relative .. "/")
        else
            table.insert(
                manifest,
                { path = relative, sha256 = serde.hash("sha256", fs.readFile(input)) }
            )
        end
    end
end
inspect("build/artifacts", "")
fs.writeFile("build/artifacts/manifest.json", serde.encode("json", manifest, true))
print("Packaged configured outputs at build/artifacts")
