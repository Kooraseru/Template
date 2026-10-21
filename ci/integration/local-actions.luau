-- ci/integration/local-actions.luau
--!strict

local LocalActions = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Task = require("@lune/task")
local Datetime = require("@lune/datetime")
local Stdio = require("@lune/stdio")

--# Functions

function LocalActions.Request(operation: string, workflow: string?): string

	assert(operation == "status" or operation == "start", "expected status or start")
	local root = "build/runtime/local-actions/"
	assert(Fs.isFile(root .. "session.json"), "Local Actions bridge is not active in this VS Code workspace")
	local session = Serde.decode("json", Fs.readFile(root .. "session.json")) :: { token: string }
	local id = Serde.hash("sha256", Datetime.now():toIsoDate() .. tostring(math.random())):sub(1, 32)
	local path = root .. id
	local request: { [string]: unknown } = { token = session.token, operation = operation }
	if operation == "start" then
		local file = workflow or "ci.yml"
		assert(file:match("^[%w%-]+%.ya?ml$"), "expected a workflow filename")
		local source = Fs.readFile(".github/workflows/" .. file)
		request.workflow = file
		request.source = source
		request.definition = Serde.decode("yaml", source)
	end
	Fs.writeFile(path .. ".tmp", Serde.encode("json", request))
	Fs.move(path .. ".tmp", path .. ".request.json")

	for _ = 1, 150 do
		if Fs.isFile(path .. ".response.json") then
			local bytes = Fs.readFile(path .. ".response.json")
			local response = Serde.decode("json", bytes) :: { ok: boolean, error: string? }
			Fs.removeFile(path .. ".request.json")
			Fs.removeFile(path .. ".response.json")
			assert(response.ok, response.error or "extension command failed")
			return bytes
		end
		Task.wait(0.1)
	end

	-- Remove unread requests; an already accepted extension command may still complete.
	Fs.removeFile(path .. ".request.json")
	error(
		"Local Actions bridge timed out; query status before retrying because the extension may already have accepted the command"
	)
end

function LocalActions.Run()

	Stdio.write(LocalActions.Request(Process.args[1] or "status", Process.args[2]) .. "\n")
end

return LocalActions
