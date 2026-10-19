-- validation/tests/rules.luau
--!strict

local Test = require("@testing")

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Files = require("../../libraries/bootstrap/files")
local Rules = require("../../libraries/registry/rules")

--# Types

type Input = { Document: unknown, Value: unknown }

--# Helpers

local function validate(input: Input): boolean
	local root = "build/tests/rules"
	Files.Reset(root)
	local success = pcall(function()
		local path = root .. "/document.json"
		Fs.writeFile(path, Serde.encode("json", input.Document))
		Rules.Validate(input.Value, Rules.Read(path))
	end)

	Files.Reset(root)

	return success
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Validation rule execution",
	Execute = validate,
	Cases = {
		{
			["Name"] = "string pattern",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["kind"] = "string",
							["pattern"] = "^%a+$",
						},
					},
				},
				["Value"] = "abc",
			},
			["Expected"] = true,
		},
		{
			["Name"] = "pattern mismatch",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["kind"] = "string",
							["pattern"] = "^%a+$",
						},
					},
				},
				["Value"] = "123",
			},
			["Expected"] = false,
		},
		{
			["Name"] = "misspelled option",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["kind"] = "string",
							["patern"] = "^%a+$",
						},
					},
				},
				["Value"] = "abc",
			},
			["Expected"] = false,
		},
		{
			["Name"] = "wrong option type",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["kind"] = "string",
							["min_length"] = "1",
						},
					},
				},
				["Value"] = "abc",
			},
			["Expected"] = false,
		},
		{
			["Name"] = "conditional false",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "value",
							["min_length"] = 1,
							["when"] = {
								["path"] = "enabled",
								["equals"] = true,
							},
						},
					},
				},
				["Value"] = {
					["enabled"] = false,
					["value"] = "",
				},
			},
			["Expected"] = true,
		},
		{
			["Name"] = "conditional true",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "value",
							["min_length"] = 1,
							["when"] = {
								["path"] = "enabled",
								["equals"] = true,
							},
						},
					},
				},
				["Value"] = {
					["enabled"] = true,
					["value"] = "",
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "missing required field",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "required",
							["exists"] = true,
						},
					},
				},
				["Value"] = {},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "required false value",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "required",
							["exists"] = true,
						},
					},
				},
				["Value"] = {
					["required"] = false,
				},
			},
			["Expected"] = true,
		},
		{
			["Name"] = "wildcard rejection",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "*",
							["kind"] = "string",
						},
					},
				},
				["Value"] = {
					"a",
					1,
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "duplicate key",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["kind"] = "array",
							["unique_by"] = "name",
						},
					},
				},
				["Value"] = {
					{
						["name"] = "a",
					},
					{
						["name"] = "a",
					},
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "object entry count",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["key_count"] = 2,
						},
					},
				},
				["Value"] = {
					["one"] = 1,
					["two"] = 2,
				},
			},
			["Expected"] = true,
		},
		{
			["Name"] = "wrong object entry count",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["key_count"] = 2,
						},
					},
				},
				["Value"] = {
					["one"] = 1,
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "filtered entry count",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["count_where"] = {
								["field"] = "type",
								["equals"] = "choice",
								["count"] = 1,
							},
						},
					},
				},
				["Value"] = {
					["one"] = {
						["type"] = "choice",
					},
					["two"] = {
						["type"] = "string",
					},
				},
			},
			["Expected"] = true,
		},
		{
			["Name"] = "wrong filtered entry count",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["count_where"] = {
								["field"] = "type",
								["equals"] = "choice",
								["count"] = 1,
							},
						},
					},
				},
				["Value"] = {
					["one"] = {
						["type"] = "string",
					},
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "prerequisite comes first",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["requires_before"] = {
								["field"] = "uses",
								["value"] = "consumer",
								["prerequisite"] = "prerequisite",
							},
						},
					},
				},
				["Value"] = {
					{
						["uses"] = "prerequisite",
					},
					{
						["uses"] = "consumer",
					},
				},
			},
			["Expected"] = true,
		},
		{
			["Name"] = "prerequisite comes too late",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["requires_before"] = {
								["field"] = "uses",
								["value"] = "consumer",
								["prerequisite"] = "prerequisite",
							},
						},
					},
				},
				["Value"] = {
					{
						["uses"] = "consumer",
					},
					{
						["uses"] = "prerequisite",
					},
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "unused prerequisite is optional",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["requires_before"] = {
								["field"] = "uses",
								["value"] = "consumer",
								["prerequisite"] = "prerequisite",
							},
						},
					},
				},
				["Value"] = {},
			},
			["Expected"] = true,
		},
		{
			["Name"] = "skip patterns cannot bypass input types",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["skip_pattern"] = "^%./",
							["kind"] = "string",
							["pattern"] = "@tag$",
						},
					},
				},
				["Value"] = 42,
			},
			["Expected"] = false,
		},
		{
			["Name"] = "malformed prerequisite definition",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["requires_before"] = {
								["field"] = "uses",
								["value"] = false,
								["prerequisite"] = "setup",
							},
						},
					},
				},
				["Value"] = {},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "malformed count filter",
			["Input"] = {
				["Document"] = {
					["rules"] = {
						{
							["path"] = "$",
							["count_where"] = {
								["field"] = false,
								["count"] = 1,
							},
						},
					},
				},
				["Value"] = {},
			},
			["Expected"] = false,
		},
	},
}

return Test.new(definition)
