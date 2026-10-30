-- repo/ci/github/pagesDeployment.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Publication = require("./publication")

local PagesDeployment = {}

function PagesDeployment.Prepare(): ()
	Publication.Output("enabled", "false")
	if Process.env.CI_DELEGATED == "true" then
		print("Pages deployment belongs to the generated execution run")
		return
	end
	local repository = Publication.Begin("PAGES")
	if not repository then
		return
	end
	local status, details = Publication.Request("GET", `repos/{repository}/pages`)
	if status == 404 then
		print("Pages publication skipped: enable Pages in repository Settings > Pages")
		return
	end
	Publication.RequireSuccess(status, "Read Pages configuration")
	if details.build_type ~= "workflow" then
		error("Pages publication requires Settings > Pages > Source = GitHub Actions", 0)
	end
	if not Fs.isFile("build/repo/pages/index.html") then
		error("Pages artifact is missing build/repo/pages/index.html", 0)
	end
	Publication.Output("path", "build/repo/pages")
	Publication.Output("enabled", "true")
end

return PagesDeployment
