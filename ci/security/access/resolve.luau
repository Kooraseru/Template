-- security/access/resolve.luau
--!strict

local ResolveAccess = {}

--# Modules

local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Configuration = require("../../libraries/registry/config")
local Outputs = require("../../libraries/bootstrap/outputs")
local Context = require("./context")
local Policy = require("./policy")
local Receipts = require("../receipts/cli")
local ResolveReleases = require("../../publication/releases/resolve")
local Fs = require("@lune/fs")

--# Functions

function ResolveAccess.Run()
	local config = Configuration.Read()
	ResolveReleases.Run()

	Receipts.Plan()

	local matrices = Serde.decode("json", Fs.readFile("build/tmp/releases/outputs.json")) :: { [string]: string }
	local canPublish = Policy.CanPublish(Context.Read(Process.env))
	local values = {
		publish = tostring(canPublish),
		runner = config.build.runner,
		rust = tostring(table.find(config.build.toolchains, "rust") ~= nil),
		cmake = tostring(table.find(config.build.toolchains, "cmake") ~= nil),
		rust_version = config.build.rust_version,
		cmake_version = config.build.cmake_version,
	}

	local capabilities: { [string]: Configuration.Capability } = {
		repository = config.repository,
		pages = config.pages,
		release = config.release,
		images = config.images,
	}

	for name, capability in capabilities do
		values[name] = tostring(capability.enabled)
		values["publish_" .. name] = tostring(canPublish and capability.publish)
	end

	values.images = matrices.images_enabled
	values.image_matrix = matrices.image_matrix
	values.build_matrix = matrices.build_matrix
	values.release_matrix = matrices.release_matrix
	values.release = matrices.release_enabled
	values.publish_release = tostring(canPublish and config.release.publish and matrices.release_enabled == "true")
	values.build_requested = matrices.build_requested
	values.receipt_ready = matrices.receipt_ready
	values.accepted_available = matrices.accepted_available
	values.local_execution = matrices.local_execution
	Outputs.Write(Process.env.GITHUB_OUTPUT, values)
end

return ResolveAccess
