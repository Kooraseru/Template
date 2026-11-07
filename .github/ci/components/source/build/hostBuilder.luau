-- .github/ci/components/source/build/hostBuilder.luau
--!strict

local Fs = require("@std/fs")
local Glob = require("@ci/bootstrap/discovery/glob")
local Toml = require("@formats/toml")

local HostBuilder = {}
HostBuilder.__index = HostBuilder

export type HostBuilder = setmetatable<{}, typeof(HostBuilder)>

function HostBuilder.new(): HostBuilder
	local fields = {}
	return setmetatable(fields, HostBuilder)
end

function HostBuilder.Run(_self: HostBuilder): ()
	if not (Fs.exists("build") and Fs.type("build") == "dir") then
		Fs.createDirectory("build", { makeParents = true })
	end

	local entries = Glob.Find("source/hosts/*/host.toml")
	if #entries == 0 then
		error("No host contracts discovered under source/hosts", 0)
	end

	for _, contractPath in entries do
		local directory = contractPath:gsub("/host%.toml$", "")
		local entry = `{directory}/init.luau`
		if not (Fs.exists(entry) and Fs.type(entry) == "file") then
			error(`{directory}: a host requires a regular init.luau implementation`, 0)
		end
		local decodedValue = Toml.decode(Fs.readFileToString(contractPath))
		if type(decodedValue) ~= "table" then error(`{contractPath}: expected a TOML table`, 0) end
		local decoded = decodedValue :: { [string]: unknown }
		if type(decoded) ~= "table" or type(decoded.artifacts) ~= "table" or #decoded.artifacts == 0 then
			error(`{contractPath}: artifacts must be a nonempty array`, 0)
		end
		for field in decoded do
			if field ~= "artifacts" and field ~= "run" then
				error(`{contractPath}: unsupported host field {tostring(field)}`, 0)
			end
		end
		local modulePath = `@workspace/{directory}`
		local loaded, host = xpcall(require, tostring, modulePath)
		if not loaded then
			error(`{entry}: unable to load host module: {host}`, 0)
		end
		if type(host) ~= "table" or type(host.Build) ~= "function" then
			error(`{entry}: host module must return a table with Build()`, 0)
		end
		local outputs: { string } = {}
		for _, output in decoded.artifacts :: { unknown } do
			if type(output) ~= "string" then error(`{contractPath}: artifacts must be strings`, 0) end
			table.insert(outputs, output)
		end
		local declaredOutputs: { [string]: boolean } = {}
		for _, output in outputs do
			if type(output) ~= "string" or not output:match("^build/run/ci%-execution/artifacts/[^/].*") then
				error(`{contractPath}: every artifact must be a path under build/run/ci-execution/artifacts`, 0)
			end
			for segment in output:gmatch("[^/]+") do
				if segment == "." or segment == ".." then
					error(`{contractPath}: unsafe artifact path {output}`, 0)
				end
			end
			if declaredOutputs[output] then
				error(`{contractPath}: duplicate artifact path {output}`, 0)
			end
			declaredOutputs[output] = true
		end
		if decoded.run ~= nil and (type(decoded.run) ~= "string" or not declaredOutputs[decoded.run]) then
			error(`{contractPath}: run must name one declared artifact`, 0)
		end
		local buildHost: () -> () = host.Build
		buildHost()
		for _, output in outputs do
			if not (Fs.exists(output) and Fs.type(output) == "file") then
				error(`{directory}: declared artifact was not produced: {output}`, 0)
			end
		end
		print(`Built host from {entry}`)
	end
end

return HostBuilder
