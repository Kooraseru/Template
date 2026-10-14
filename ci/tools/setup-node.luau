--!strict
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local definition: any = serde.decode("json", fs.readFile("ci/tools/node.json"))
local platform = assert(definition.platforms[process.os .. "-" .. process.arch], "unsupported Node platform")
local root = assert(process.env.RUNNER_TEMP, "missing runner temporary directory") .. "/ci-node"
fs.writeDir(root)
local response = net.request(definition.url .. platform.file)
assert(response.ok, "Node download failed")
assert(serde.hash("sha256", response.body) == platform.sha256, "Node checksum mismatch")
local archive = root .. "/" .. platform.file
fs.writeFile(archive, response.body)
local destination = root .. "/runtime"
fs.writeDir(destination)
local result
if process.os == "windows" then
    result = process.exec("unzip", { "-o", archive, "-d", destination })
    destination ..= "/" .. platform.file:gsub("%.zip$", "")
else
    result = process.exec("tar", { "-xf", archive, "--strip-components=1", "-C", destination })
    destination ..= "/bin"
end
assert(result.ok, "Node extraction failed: " .. result.stderr)
local output = assert(process.env.GITHUB_PATH, "missing workflow path file")
local existing = if fs.isFile(output) then fs.readFile(output) else ""
fs.writeFile(output, existing .. destination .. "\n")
print("Installed checksum-verified Node " .. definition.version)
