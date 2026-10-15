-- ci/tools/setup-node.luau
--!strict
local Fs = require("@lune/fs")
local Net = require("@lune/net")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local definition = Serde.decode("json", Fs.readFile("ci/tools/node.json")) :: { version: string, url: string, platforms: { [string]: { file: string, sha256: string } } }
local platform = assert(definition.platforms[Process.os .. "-" .. Process.arch], "unsupported Node platform")
local root = assert(Process.env.RUNNER_TEMP, "missing runner temporary directory") .. "/ci-node"
Fs.writeDir(root)
local response = Net.request(definition.url .. platform.file)
assert(response.ok, "Node download failed")
assert(Serde.hash("sha256", response.body) == platform.sha256, "Node checksum mismatch")
local archive = root .. "/" .. platform.file
Fs.writeFile(archive, response.body)
local destination = root .. "/runtime"
Fs.writeDir(destination)
local result
if Process.os == "windows" then
    result = Process.exec("unzip", { "-o", archive, "-d", destination })
    destination ..= "/" .. platform.file:gsub("%.zip$", "")
else
    result = Process.exec("tar", { "-xf", archive, "--strip-components=1", "-C", destination })
    destination ..= "/bin"
end
assert(result.ok, "Node extraction failed: " .. result.stderr)
local output = assert(Process.env.GITHUB_PATH, "missing workflow path file")
local existing = if Fs.isFile(output) then Fs.readFile(output) else ""
Fs.writeFile(output, existing .. destination .. "\n")
print("Installed checksum-verified Node " .. definition.version)
