-- .github/ci/integrations/github/publication/pagesDeployment.luau
--!strict

local Fs = require("@std/fs")
local Publication = require("@ci/integrations/github/publication")

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
	if not Fs.exists("build/github/pages/index.html") or Fs.type("build/github/pages/index.html") ~= "file" then
		print("::warning::Pages deployment skipped: no completed site artifact is available")
		return false
	end
	Publication.Output("path", "build/github/pages")
	Publication.Output("enabled", "true")
	return true
end

return PagesDeployment
