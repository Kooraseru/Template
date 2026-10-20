-- .github/integration/local-actions.luau
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

function LocalActions.Request(operation: string): string

	assert(operation == "status" or operation == "start", "expected status or start")
	local root = ".kero/.runtime/local-actions/"
	assert(Fs.isFile(root .. "session.json"), "Local Actions bridge is not active in this VS Code workspace")
	local session = Serde.decode("json", Fs.readFile(root .. "session.json")) :: { token: string }
	local id = Serde.hash("sha256", Datetime.now():toIsoDate() .. tostring(math.random())):sub(1, 32)
	local path = root .. id
	Fs.writeFile(path .. ".tmp", Serde.encode("json", { token = session.token, operation = operation }))
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

	Stdio.write(LocalActions.Request(Process.args[1] or "status") .. "\n")
end

return LocalActions
