-- ci/components/build/HostBuilder.luau
--!strict

local Fs = require("@lune/fs")
local Glob = require("../../bootstrap/glob")

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
		local modulePath = "../../../" .. entry:gsub("/init%.luau$", "")
		local host = require(modulePath)
		if type(host) ~= "function" then
			error(`{entry}: host module must return a callable function`, 0)
		end
		host()
		print(`Built host from {entry}`)
	end
end

return HostBuilder
