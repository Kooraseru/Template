-- ci/validation/tests/catalogue.luau
--!strict

local Test = require("../../libraries/testing/test")

--# Modules

local Cases = require("../../libraries/testing/cases")
local Catalogue = require("../../libraries/registry/catalogue")
local Config = require("../../libraries/registry/config")

--# Data

local baseline: Cases.Patch = {
	["patch"] = {
		["config.build.matrix"] = {},
		["config.build.targets"] = {
			"alpine-gcc-x64",
		},
		["config.images.names"] = {
			"alpine-gcc-x64",
		},
		["config.images.enabled"] = true,
	},
}

--# Helpers

local function validate(input: Cases.Patch): boolean
	return (
		pcall(function()
			Catalogue.Validate(Cases.Apply(Cases.Apply(Catalogue.Read(Config.Read()), baseline), input))
		end)
	)
end

--# Declaration

local definition: Test.Definition<Cases.Patch, boolean> = {
	Name = "Catalogue",
	Execute = validate,
	Cases = {
		{
			["Name"] = "baseline",
			["Input"] = {},
			["Expected"] = true,
		},
		{
			["Name"] = "unknown image",
			["Input"] = {
				["patch"] = {
					["config.images.names"] = {
						"missing",
					},
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "unknown target",
			["Input"] = {
				["patch"] = {
					["config.build.targets"] = {
						"missing",
					},
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "missing selected image",
			["Input"] = {
				["patch"] = {
					["config.images.names"] = {},
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "image jobs disabled",
			["Input"] = {
				["patch"] = {
					["config.images.enabled"] = false,
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "duplicate image",
			["Input"] = {
				["patch"] = {
					["images"] = {},
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "native only without images",
			["Input"] = {
				["patch"] = {
					["config.build.targets"] = {
						"windows-msvc-x64",
					},
					["config.images.names"] = {},
					["config.images.enabled"] = false,
				},
			},
			["Expected"] = true,
		},
		{
			["Name"] = "invalid platform",
			["Input"] = {
				["patch"] = {
					["images.1.platform"] = "linux/mips",
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "invalid package expression",
			["Input"] = {
				["patch"] = {
					["images.1.packages"] = {
						"gcc; exit 0",
					},
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "unmatched runner architecture",
			["Input"] = {
				["patch"] = {
					["images.1.runner"] = "ubuntu-24.04-arm",
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "missing base digest",
			["Input"] = {
				["patch"] = {
					["images.1.base"] = "alpine:latest",
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "escaping recipe",
			["Input"] = {
				["patch"] = {
					["images.1.recipe"] = "linux/../../Dockerfile",
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "target image mismatch",
			["Input"] = {
				["patch"] = {
					["targets.1.profile"] = "clang",
				},
			},
			["Expected"] = false,
		},
	},
}

return Test.new(definition)
