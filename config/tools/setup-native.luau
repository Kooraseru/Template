-- config/tools/setup-native.luau
--!strict

local SetupNative = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Rules = require("../../libraries/registry/rules")
local Outputs = require("../../libraries/bootstrap/outputs")

--# Functions

function SetupNative.Run()
	local document = Rules.Entries(Serde.decode("json", Fs.readFile("config/tools/ruleset.json")))
	local version = Rules.Entries(document.native).toolchain
	assert(type(version) == "string" and version:match("^%d+%.%d+%.%d+$"), "missing native Rust toolchain")
	Outputs.Write(Process.env.GITHUB_OUTPUT, { toolchain = version })
end

return SetupNative
