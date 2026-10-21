-- validation/tests/config.luau
--!strict

local Test = require("@testing")

--# Modules

local Config = require("../../libraries/registry/config")
local Cases = require("../../libraries/testing/cases")

--# Types

type Input = Cases.Patch & { Path: string? }

--# Helpers

local function validate(input: Input): boolean
	if input.Path then
		return (pcall(Config.Relative, input.Path))
	end

	return (pcall(Config.Validate, Cases.Apply(Config.Read(), input)))
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Project configuration",
	Execute = validate,
	Cases = {
		{
			["Name"] = "default configuration",
			["Input"] = {
				["patch"] = {},
			},
			["Expected"] = true,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "self-hosted runner",
			["Input"] = {
				["patch"] = {
					["build.runner"] = "self-hosted",
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "Git metadata publication",
			["Input"] = {
				["patch"] = {
					["repository.include"] = {
						".git",
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "build output publication",
			["Input"] = {
				["patch"] = {
					["repository.include"] = {
						"build",
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "package outside build",
			["Input"] = {
				["patch"] = {
					["build.package_paths"] = {
						"src",
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "empty image list",
			["Input"] = {
				["patch"] = {
					["images.enabled"] = true,
					["images.names"] = {},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "unversioned Rust",
			["Input"] = {
				["patch"] = {
					["build.toolchains"] = {
						"rust",
					},
					["build.rust_version"] = "",
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "unversioned CMake",
			["Input"] = {
				["patch"] = {
					["build.toolchains"] = {
						"cmake",
					},
					["build.cmake_version"] = "latest",
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "command string",
			["Input"] = {
				["patch"] = {
					["build.commands"] = {
						"cargo test",
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "empty executable",
			["Input"] = {
				["patch"] = {
					["build.commands"] = {
						{
							"",
						},
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "commands dictionary",
			["Input"] = {
				["patch"] = {
					["build.commands"] = {
						["named"] = {
							"cargo",
							"test",
						},
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "recursive package destination",
			["Input"] = {
				["patch"] = {
					["build.package_paths"] = {
						"build/artifacts",
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "build root package",
			["Input"] = {
				["patch"] = {
					["build.package_paths"] = {
						"build/",
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "reserved metadata",
			["Input"] = {
				["patch"] = {
					["build.package_paths"] = {
						"build/manifest.json",
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "duplicate image",
			["Input"] = {
				["patch"] = {
					["images.names"] = {
						"smoke",
						"smoke",
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "platform matrix",
			["Input"] = {
				["patch"] = {
					["build.matrix"] = {
						{
							["name"] = "linux",
							["runner"] = "ubuntu-latest",
						},
						{
							["name"] = "windows",
							["runner"] = "windows-latest",
						},
						{
							["name"] = "macos",
							["runner"] = "macos-latest",
						},
					},
				},
			},
			["Expected"] = true,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "duplicate matrix name",
			["Input"] = {
				["patch"] = {
					["build.matrix"] = {
						{
							["name"] = "linux",
							["runner"] = "ubuntu-latest",
						},
						{
							["name"] = "linux",
							["runner"] = "ubuntu-latest",
						},
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "matrix self-hosted runner",
			["Input"] = {
				["patch"] = {
					["build.matrix"] = {
						{
							["name"] = "unsafe",
							["runner"] = "self-hosted",
						},
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "matrix path traversal name",
			["Input"] = {
				["patch"] = {
					["build.matrix"] = {
						{
							["name"] = "../unsafe",
							["runner"] = "ubuntu-latest",
						},
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "omitted optional build fields",
			["Input"] = {
				["remove"] = {
					"build.runner",
					"build.matrix",
					"build.targets",
					"build.toolchains",
					"build.rust_version",
					"build.cmake_version",
					"build.commands",
					"build.package_paths",
				},
			},
			["Expected"] = true,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "omitted optional page title",
			["Input"] = {
				["remove"] = {
					"pages.title",
				},
			},
			["Expected"] = true,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "omitted Rust version when enabled",
			["Input"] = {
				["patch"] = {
					["build.toolchains"] = {
						"rust",
					},
				},
				["remove"] = {
					"build.rust_version",
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "omitted CMake version when enabled",
			["Input"] = {
				["patch"] = {
					["build.toolchains"] = {
						"cmake",
					},
				},
				["remove"] = {
					"build.cmake_version",
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "omitted images while disabled",
			["Input"] = {
				["patch"] = {
					["images.enabled"] = false,
					["images.publish"] = false,
				},
				["remove"] = {
					"images.names",
				},
			},
			["Expected"] = true,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "omitted images while enabled",
			["Input"] = {
				["patch"] = {
					["images.enabled"] = true,
				},
				["remove"] = {
					"images.names",
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "missing required build category",
			["Input"] = {
				["remove"] = {
					"build",
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "missing required publication flag",
			["Input"] = {
				["remove"] = {
					"release.publish",
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "omitted image publication flag",
			["Input"] = {
				["remove"] = {
					"images.publish",
				},
			},
			["Expected"] = true,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "reject registry publication",
			["Input"] = {
				["patch"] = {
					["images.publish"] = true,
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "reserved source provenance path",
			["Input"] = {
				["patch"] = {
					["build.package_paths"] = {
						"build/provenance.json",
					},
				},
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "Path ../secret",
			["Input"] = {
				["Path"] = "../secret",
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "Path /tmp/file",
			["Input"] = {
				["Path"] = "/tmp/file",
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "Path C:/secret",
			["Input"] = {
				["Path"] = "C:/secret",
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "Path src/../secret",
			["Input"] = {
				["Path"] = "src/../secret",
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "Path src\\file",
			["Input"] = {
				["Path"] = "src\\file",
			},
			["Expected"] = false,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "Path src",
			["Input"] = {
				["Path"] = "src",
			},
			["Expected"] = true,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "Path assets/icon.png",
			["Input"] = {
				["Path"] = "assets/icon.png",
			},
			["Expected"] = true,
			["Compare"] = Test.Equal,
		},
		{
			["Name"] = "Path build/artifacts/package.zip",
			["Input"] = {
				["Path"] = "build/artifacts/package.zip",
			},
			["Expected"] = true,
			["Compare"] = Test.Equal,
		},
	},
}

return Test.new(definition)
