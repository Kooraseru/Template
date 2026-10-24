-- ci/integration/configure-editor.luau
--!strict

local ConfigureEditor = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../validation/rules")

--# Functions

function ConfigureEditor.Merge(existing: unknown, defaults: unknown): { [string | number]: unknown }
	local merged = table.clone(Rules.Entries(existing))

	for key, value in Rules.Entries(defaults) do
		assert(type(key) == "string", "invalid editor setting")

		if key:sub(1, 1) == "[" and type(value) == "table" then
			local section = table.clone(Rules.Entries(merged[key] or {}))

			for setting, selected in Rules.Entries(value) do
				section[setting] = selected
			end

			merged[key] = section
		else
			merged[key] = value
		end
	end

	return merged
end

function ConfigureEditor.Run()
	local path = ".vscode/settings.json"
	local defaults = Serde.decode("json", Fs.readFile("config/luau/luau-lsp/settings.json"))
	local existing = if Fs.isFile(path) then Serde.decode("json", Fs.readFile(path)) else {}
	Fs.writeDir(".vscode")
	Fs.writeFile(path, Serde.encode("json", ConfigureEditor.Merge(existing, defaults), true) .. "\n")
	-- act reads .actrc from the workspace root, not an arbitrary config/ directory.
	-- Generate a disposable local adapter from the tracked source of truth.
	Fs.writeFile(".actrc", Fs.readFile("config/docker/actrc"))
end

return ConfigureEditor
