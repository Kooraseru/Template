-- repo/ci/dependencies/pandoc.luau
--!strict

local Process = require("@lune/process")

local Pandoc = {}
local ready = false

-- Install only when rendering needs the tool, rather than during bootstrap.
function Pandoc.Ensure(): ()
	if ready then
		return
	end
	local found, result = xpcall(Process.exec, tostring, "pandoc", { "--version" })
	if found and result.ok then
		ready = true
		return
	end
	if Process.os ~= "linux" or Process.env.GITHUB_ACTIONS ~= "true" then
		error("Pages rendering requires pandoc on PATH; install Pandoc before running local CI", 0)
	end
	for _, arguments in
		{
			{ "apt-get", "update" },
			{ "apt-get", "install", "--yes", "--no-install-recommends", "pandoc" },
		}
	do
		local installed = Process.exec("sudo", arguments, { stdio = "inherit" })
		if not installed.ok then
			error("Unable to install the Pages component's Pandoc dependency", 0)
		end
	end
	local verified = Process.exec("pandoc", { "--version" })
	if not verified.ok then
		error("Pandoc installation did not produce a working executable", 0)
	end
	ready = true
end

return Pandoc
