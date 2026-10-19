-- validation/workshop.luau
--!strict

local Workshop = {}

--# Modules

local Shape = require("../libraries/registry/shape")

--# Types

export type Asset = { path: string, requires: string }
export type Descriptor = { id: string, name: string, assets: { Asset } }
export type File = { Path: string, Bytes: number, Executable: boolean }
export type Limits = { Files: number, Bytes: number, AssetBytes: number }

--# Functions

function Workshop.Validate(value: unknown): Descriptor
	-- Deliberately independent of the plugin descriptor and its execution fields.
	local fields = Shape.Object(value, { "id", "name", "assets" })
	local assets: { Asset } = {}
	local paths: { [string]: boolean } = {}

	for _, raw in Shape.Sequence(fields.assets) do
		local asset = Shape.Object(raw, { "path", "requires" })
		local path = Shape.Relative(asset.path)
		assert(not paths[path], "duplicate Workshop asset: " .. path)
		paths[path] = true
		table.insert(assets, { path = path, requires = Shape.Text(asset.requires, "provider capability") })
	end

	assert(#assets > 0, "Workshop item needs at least one asset")

	return {
		id = Shape.Text(fields.id, "content identifier"),
		name = Shape.Text(fields.name, "display name"),
		assets = assets,
	}
end

function Workshop.Inventory(descriptor: Descriptor, files: { File }, limits: Limits)
	assert(limits.Files >= 1 and limits.Bytes >= 0 and limits.AssetBytes >= 0, "invalid content limits")
	assert(#files <= limits.Files, "Workshop file count limit exceeded")
	local declared: { [string]: boolean } = { ["workshop.toml"] = true }

	for _, asset in descriptor.assets do
		assert(asset.path ~= "workshop.toml", "descriptor cannot be an asset")
		declared[asset.path] = true
	end

	local seen: { [string]: boolean } = {}
	local total = 0

	for _, file in files do
		local path = Shape.Relative(file.Path)
		assert(declared[path], "undeclared Workshop file: " .. path)
		assert(not seen[path], "duplicate inventory path: " .. path)
		assert(not file.Executable, "executable Workshop content is prohibited: " .. path)
		assert(file.Bytes >= 0 and file.Bytes % 1 == 0 and file.Bytes <= limits.AssetBytes, "asset size limit exceeded")
		seen[path] = true
		total += file.Bytes
		assert(total <= limits.Bytes, "Workshop size limit exceeded")
	end

	for path in declared do
		assert(seen[path], "missing Workshop file: " .. path)
	end
end

function Workshop.Resolve(
	descriptor: Descriptor,
	available: { [string]: { string } },
	selections: { [string]: string }?
): { [string]: string }
	local result: { [string]: string } = {}
	local selected = selections or {}

	for _, asset in descriptor.assets do
		local providers = available[asset.requires] or {}
		local choice = selected[asset.requires]
		assert(#providers > 0, "missing provider: " .. asset.requires)
		assert(choice ~= nil or #providers == 1, "ambiguous provider: " .. asset.requires)
		local provider = choice or providers[1]
		assert(table.find(providers, provider), "selected provider does not support: " .. asset.requires)
		result[asset.path] = provider
	end

	return result
end

return Workshop
