-- repo/ci/github/pagesDeployment.luau
--!strict

local Fs = require("@lune/fs")
local Publication = require("./publication")

local PagesDeployment = {}

function PagesDeployment.Prepare(): boolean
	Publication.Output("enabled", "false")
	local repository = Publication.Begin("PAGES")
	if not repository then
		return false
	end
	local status, details = Publication.Request("GET", `repos/{repository}/pages`)
	if status == 404 then
		print("Pages publication skipped: enable Pages in repository Settings > Pages")
		return false
	end
	Publication.RequireSuccess(status, "Read Pages configuration")
	if details.build_type ~= "workflow" then
		error("Pages publication requires Settings > Pages > Source = GitHub Actions", 0)
	end
	if not Fs.isFile("build/repo/pages/index.html") then
		print("::warning::Pages deployment skipped: no completed site artifact is available")
		return false
	end
	Publication.Output("path", "build/repo/pages")
	Publication.Output("enabled", "true")
	return true
end

return PagesDeployment
