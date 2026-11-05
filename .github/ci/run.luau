-- .github/ci/run.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")

local selector = Process.args[1]
local selected = if selector == "--" then Process.args[2] else selector
if not selected or not selected:match("^[%w_-]+$") then
	error("usage: lune run .github/ci/run.luau <host-name>", 0)
end

local contractPath = `source/hosts/{selected}/host.toml`
if not Fs.isFile(contractPath) then
	error(`unknown host {selected}; no contract at {contractPath}`, 0)
end
local contract = Serde.decode("toml", Fs.readFile(contractPath))
if type(contract) ~= "table" or type(contract.artifacts) ~= "table" then
	error(`invalid host contract: {contractPath}`, 0)
end
local artifacts: { string } = contract.artifacts
if #artifacts == 0 then
	error(`host contract has no artifacts: {contractPath}`, 0)
end
for _, artifact in artifacts do
	if not Fs.isFile(artifact) then
		error(
			`missing {artifact}; build first with bash .github/ci/tooling/lune/bootstrap.sh run .github/ci/entry.luau`,
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

local options: Process.ExecOptions = {
	cwd = Process.cwd,
	stdio = "inherit",
}
local result = Process.exec(executable, {}, options)
if not result.ok then
	Process.exit(result.code)
end
