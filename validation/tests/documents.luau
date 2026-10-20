-- validation/tests/documents.luau
--!strict

local Test = require("@testing")

--# Modules

local C = require("../../libraries/bootstrap/canonical")
local D = require("../../libraries/bootstrap/documents")
local Native = require("../../libraries/bootstrap/native")
local Commands = require("../../libraries/bootstrap/commands")
local Process = require("@lune/process")
local Client = require("../../publication/releases/client")

--# Helpers

local function execute(kind: string): boolean
	if kind == "lossless" then
		local value = C.Decode('{"valid":"Unicode \\u00e9","surrogate":"\\ud800","array":[],"null":null}')
		assert(type(D.Get(value, "valid")) == "string")
		local normalized = D.Set(value, "valid", D.Required(value, "valid"))
		assert(C.Encode(value) == C.Encode(normalized) and C.Hash(value) == C.Hash(normalized))
		assert(type(D.Get(value, "surrogate")) == "table" and not pcall(D.Text, value, "surrogate"))
		assert(D.Equal(D.Get(value, "array"), C.Array({})) and D.Equal(D.Get(value, "null"), C.Null))
	elseif kind == "stdin" then
		assert(Commands.Run(Native.Ensure(), { "numbers" }, '["1.5000000000000000"]') == '["1.5"]')
	elseif kind == "key-boundary" then
		assert(not pcall(Native.Call, "keyfile", { path = Process.cwd .. "/README.md", workspace = Process.cwd }))
		assert(
			not pcall(
				Native.Call,
				"keygen",
				{ path = Process.cwd .. "/build/forbidden-signing-key.pem", workspace = Process.cwd }
			)
		)
	elseif kind == "client" then
		local previous = Commands.Execute
		local calls = 0
		Commands.Execute = function(
			_program: string,
			args: { string },
			input: string?,
			_cwd: string?,
			_env: { [string]: string }?
		): Process.Execution
			calls += 1
			assert(args[1] == "api")
			if args[2]:find("retry", 1, true) and calls == 1 then
				return { ok = false, code = 1, stdout = "", stderr = "HTTP 503" }
			end
			if args[2]:find("missing", 1, true) then
				return { ok = false, code = 1, stdout = "", stderr = "HTTP 404" }
			end
			if args[2]:find("binary", 1, true) then
				return { ok = true, code = 0, stdout = "\0\255asset", stderr = "" }
			end
			if args[2]:find("write", 1, true) then
				assert(input == '{"message":"exact bytes"}')
			end
			return { ok = true, code = 0, stdout = '{"ok":true}', stderr = "" }
		end
		local ok, failure = pcall(function()
			local api = Client.new("owner/project")
			assert(D.Get(assert(api.Request("/retry")), "ok") == true and calls == 2)
			assert(api.Request("/missing", { Missing = true }) == nil)
			assert(api.Bytes("/binary", { Binary = true }) == "\0\255asset")
			assert(D.Get(api.JSON("POST", "/write", C.Object({ message = "exact bytes" })), "ok") == true)
			local before = calls
			assert(not pcall(api.Request, "https://untrusted.example/upload", nil))
			assert(calls == before, "API token must not be forwarded to an unexpected host")
		end)
		Commands.Execute = previous
		assert(ok, tostring(failure))
	else
		error("unknown bootstrap case")
	end
	return true
end

local function cases(): { Test.Case<string, boolean> }
	local result: { Test.Case<string, boolean> } = {}
	for _, kind in { "lossless", "stdin", "key-boundary", "client" } do
		table.insert(result, { Name = kind, Input = kind, Expected = true })
	end
	return result
end

--# Declaration

local definition: Test.Definition<string, boolean> =
	{ Name = "Direct Luau byte and API boundaries", Execute = execute, Cases = cases() }

return Test.new(definition)
