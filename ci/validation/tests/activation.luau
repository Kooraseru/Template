-- validation/tests/activation.luau
--!strict

local Test = require("@testing")

--# Modules

local Plugins = require("../plugins")

--# Types

type Input = { Permissions: { string }, Granted: { string }, Methods: { [string]: unknown }, Extra: boolean? }

--# Helpers

local function validate(input: Input): boolean

	local registrations: { [string]: unknown } = { ["example.read"] = input.Methods }

	if input.Extra then
		registrations["shell.execute"] = {}
	end

	return (
		pcall(Plugins.ValidateActivation, {
			id = "example.reader",
			provides = { "example.read" },
			requires = {},
			permissions = input.Permissions,
			entry = { mode = "worker", path = "bin/provider" },
		}, {
			Contract = { Capabilities = { "example.read" }, Permissions = { "document.read" }, Modes = { "worker" } },
			Bundled = false,
			Granted = input.Granted,
			Interfaces = { ["example.read"] = { "Probe", "Read" } },
		}, registrations)
	)
end

--# Declaration

local function noop() end

local definition: Test.Definition<Input, boolean> = {
	Name = "Host-owned plugin authorization and API shapes",
	Execute = validate,
	Cases = {
		{
			Name = "Authorized provider implements host API",
			Input = {
				Permissions = { "document.read" },
				Granted = { "document.read" },
				Methods = { Probe = noop, Read = noop },
			},
			Expected = true,
		},
		{
			Name = "Request is not a grant",
			Input = { Permissions = { "document.read" }, Granted = {}, Methods = { Probe = noop, Read = noop } },
			Expected = false,
		},
		{
			Name = "Administrator access is outside host API",
			Input = {
				Permissions = { "shell.administrator" },
				Granted = { "shell.administrator" },
				Methods = { Probe = noop, Read = noop },
			},
			Expected = false,
		},
		{
			Name = "Missing implementation method",
			Input = { Permissions = {}, Granted = {}, Methods = { Probe = noop } },
			Expected = false,
		},
		{
			Name = "Non-callable implementation method",
			Input = { Permissions = {}, Granted = {}, Methods = { Probe = noop, Read = true } },
			Expected = false,
		},
		{
			Name = "Undeclared API method",
			Input = { Permissions = {}, Granted = {}, Methods = { Probe = noop, Read = noop, Shell = noop } },
			Expected = false,
		},
		{
			Name = "Undeclared execution capability",
			Input = { Permissions = {}, Granted = {}, Methods = { Probe = noop, Read = noop }, Extra = true },
			Expected = false,
		},
	},
}

return Test.new(definition)
