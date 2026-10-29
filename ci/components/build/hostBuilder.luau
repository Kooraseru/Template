-- ci/components/build/HostBuilder.luau
--!strict

local Fs = require("@lune/fs")
local Glob = require("@ci/bootstrap/glob")

const HOST_MODULE_PREFIX = "../../../"

local HostBuilder = {}
HostBuilder.__index = HostBuilder

export type HostBuilder = setmetatable<{}, typeof(HostBuilder)>

function HostBuilder.new(): HostBuilder
	local fields = {}
	return setmetatable(fields, HostBuilder)
end

function HostBuilder.Run(self: HostBuilder): ()
	if not Fs.isDir("build") then
		Fs.writeDir("build")
	end

	local entries = Glob.Find("source/hosts/*/init.luau")
	if #entries == 0 then
		error("No conforming host modules discovered", 0)
	end

	for _, entry in entries do
		local modulePath = `{HOST_MODULE_PREFIX}{entry:gsub("/init%.luau$", "")}`
		local loaded, host = xpcall(require, tostring, modulePath)
		if not loaded then
			error(`{entry}: unable to load host module: {host}`, 0)
		end
		if type(host) ~= "function" then
			error(`{entry}: host module must return a callable function`, 0)
		end
		local buildHost: () -> () = host
		buildHost()
		print(`Built host from {entry}`)
	end
end

return HostBuilder
