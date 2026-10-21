-- ci/integration/configure-editor.luau
--!strict

local ConfigureEditor = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../../libraries/registry/rules")

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
	local defaults = Serde.decode("json", Fs.readFile(".luau-lsp/settings.json"))
	local existing = if Fs.isFile(path) then Serde.decode("json", Fs.readFile(path)) else {}
	Fs.writeDir(".vscode")
	Fs.writeFile(path, Serde.encode("json", ConfigureEditor.Merge(existing, defaults), true) .. "\n")
end

return ConfigureEditor
