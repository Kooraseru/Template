-- ci/components/documentation/pages/build/siteBuilder.luau
--!strict

-- Starlight is the renderer; this component only owns the CI build contract.
local Fs = require("@std/fs")
local Process = require("@lute/process")

local SiteBuilder = {}
SiteBuilder.__index = SiteBuilder
export type SiteBuilder = setmetatable<{}, typeof(SiteBuilder)>

function SiteBuilder.new(): SiteBuilder
	return setmetatable({}, SiteBuilder)
end

function SiteBuilder.Run(_self: SiteBuilder): ()
	local result = Process.run({ "node", "ci/components/documentation/pages/build/starlight/build.cjs" }, {
		cwd = Process.cwd(),
		stdio = "inherit",
	})
	if not result.ok then
		error(`Starlight documentation build failed (exit {result.exitcode})`, 0)
	end
	if not Fs.exists("build/github/pages/index.html") or Fs.type("build/github/pages/index.html") ~= "file" then
		error("Starlight did not produce build/github/pages/index.html", 0)
	end
end

return SiteBuilder
