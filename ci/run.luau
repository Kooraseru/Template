-- ci/run.luau
--!strict

local Fs = require("@std/fs")
local Process = require("@lute/process")
local Toml = require("@formats/toml")

local selector = Process.args[2]
local selected = if selector == "--" then Process.args[3] else selector
if not selected or not selected:match("^[%w_-]+$") then
	error("usage: lute run ci/run.luau <host-name>", 0)
end

local contractPath = `source/hosts/{selected}/host.toml`
if not Fs.exists(contractPath) or Fs.metadata(contractPath).type ~= "file" then
	error(`unknown host {selected}; no contract at {contractPath}`, 0)
end
local decodedContract = Toml.decode(Fs.readFileToString(contractPath))
if type(decodedContract) ~= "table" then
	error(`invalid host contract: {contractPath}`, 0)
end
local contract = decodedContract :: { [string]: unknown }
if type(contract.artifacts) ~= "table" then
	error(`invalid host contract: {contractPath}`, 0)
end
local artifacts = contract.artifacts :: { string }
if #artifacts == 0 then
	error(`host contract has no artifacts: {contractPath}`, 0)
end

for _, artifact in artifacts do
	if not Fs.exists(artifact) or Fs.metadata(artifact).type ~= "file" then
		error(
			`missing {artifact}; build first with node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run ci/init.luau`,
			0
		)
	end
end

local executable = contract.run

if executable == nil then
	print(`Host {selected} produced {#artifacts} artifact(s); no run artifact is declared`)
	for _, artifact in artifacts do
		print(artifact)
	end
	return
end

if type(executable) ~= "string" or not table.find(artifacts, executable) then
	error(`host run artifact is not declared by {contractPath}`, 0)
end

local options: Process.ProcessRunOptions = {
	cwd = Process.cwd(),
	stdio = "inherit",
}
local result = Process.run({ executable }, options)
if not result.ok then
	Process.exit(result.exitcode)
end
