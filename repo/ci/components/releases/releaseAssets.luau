-- repo/ci/components/releases/releaseAssets.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Glob = require("@ci/bootstrap/glob")

local ReleaseAssets = {}
export type Asset = { name: string, path: string, digest: string }

function ReleaseAssets.Stage(patterns: unknown, directory: string, commit: string): { Asset }
	local assets: { Asset } = {}
	if patterns == nil then
		return assets
	end
	if type(patterns) ~= "table" then
		error("release.assets must be an array of build-output globs", 0)
	end
	if #patterns == 0 then
		return assets
	end
	local head = Process.exec("git", { "rev-parse", "HEAD" })
	if not head.ok or head.stdout:gsub("%s+$", "") ~= commit then
		error(
			"Release assets must come from the checked-out release source commit; refusing to attach another commit's binaries",
			0
		)
	end
	local sources: { [string]: boolean } = {}
	local names: { [string]: boolean } = {}
	for index, pattern in patterns do
		if
			type(index) ~= "number"
			or type(pattern) ~= "string"
			or pattern:sub(1, 6) ~= "build/"
			or pattern:find("\\", 1, true)
			or pattern:find("[:%c]")
		then
			error("release.assets must contain safe globs under build/", 0)
		end
		for segment in pattern:gmatch("[^/]+") do
			if segment == "." or segment == ".." then
				error("Unsafe release asset glob", 0)
			end
		end
		if Glob.Overlaps(pattern, "build/repo/**") then
			error("Release assets must select build deliverables outside generated repository content", 0)
		end
		local count = 0
		for _, path in Glob.Find(pattern) do
			local metadata = Fs.metadata(path)
			if metadata.kind == "dir" then
				continue
			end
			if metadata.kind ~= "file" then
				error(`Release asset is not a regular file: {path}`, 0)
			end
			count += 1
			if sources[path] then
				continue
			end
			sources[path] = true
			local name = path:match("([^/]+)$")
			if not name or not name:match("^[%w][%w_.%-]*$") or names[name:lower()] then
				error(`Duplicate or unsafe release asset filename: {path}`, 0)
			end
			names[name:lower()] = true
			Fs.writeDir(directory)
			local destination = `{directory}/{name}`
			Fs.copy(path, destination)
			local asset: Asset = {
				name = name,
				path = destination,
				digest = "sha256:" .. Serde.hash("sha256", Fs.readFile(destination)),
			}
			table.insert(assets, asset)
		end
		if count == 0 then
			error(`Release asset glob matches no files: {pattern}`, 0)
		end
	end
	table.sort(assets, function(left: Asset, right: Asset): boolean
		return left.name < right.name
	end)
	return assets
end

return ReleaseAssets
