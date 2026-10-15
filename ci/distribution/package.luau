-- ci/distribution/package.luau
--!strict
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Process = require("@lune/process")
local Config = require("../lib/config")
local config = Config.Read()
local Files = require("../lib/files")
local spec: Config.BuildSpec? = nil
if Process.env.CI_BUILD_SPEC then
    spec = Serde.decode("json", Process.env.CI_BUILD_SPEC) :: Config.BuildSpec
end
if spec then config.build = spec.build end
Files.Reset("build/artifacts")
local manifest = {}
for _, path in config.build.package_paths do
    assert(Fs.isFile(path) or Fs.isDir(path), "missing configured package output: " .. path)
    assert(
        path ~= "build/artifacts" and path:sub(1, 16) ~= "build/artifacts/",
        "package cannot copy itself"
    )
    local destination = "build/artifacts/" .. path:sub(7)
    Files.Copy(path, destination)
end
local archive =
    Process.exec("tar", { "-czf", "build/distribution.tar.gz", "-C", "build/artifacts", "." })
assert(archive.ok, "package archive failed: " .. archive.stderr)
Files.Copy("build/distribution.tar.gz", "build/artifacts/distribution.tar.gz")
if spec then
    local provenance = Fs.readFile("build/tmp/releases/execution.json")
    local metadata = Serde.decode("json", provenance) :: { source_sha: string, fingerprint: string }
    assert(metadata.source_sha == spec.source_sha and metadata.fingerprint == spec.fingerprint,
        "execution provenance does not match the package target")
    -- Preserve JSON arrays exactly; an empty Luau table re-encodes as an object.
    Fs.writeFile("build/artifacts/provenance.json", provenance)
end
local function inspect(path: string, prefix: string)
    for _, name in Fs.readDir(path) do
        local input = path .. "/" .. name
        local relative = prefix .. name
        if Fs.isDir(input) then
            inspect(input, relative .. "/")
        else
            table.insert(
                manifest,
                { path = relative, sha256 = Serde.hash("sha256", Fs.readFile(input)) }
            )
        end
    end
end
inspect("build/artifacts", "")
Fs.writeFile("build/artifacts/manifest.json", Serde.encode("json", manifest, true))
print("Packaged configured outputs at build/artifacts")
