--!strict

-- Keep the current findings by owner and publish a snapshot after each update.
local Contracts = require("@ci/preflight/contracts")

local Diagnostics = {}
Diagnostics.__index = Diagnostics

type Fields = {
	entriesByOwner: { [string]: { Contracts.Diagnostic } },
	onUpdate: (({ Contracts.Diagnostic }) -> ())?,
}

export type Diagnostics = setmetatable<Fields, typeof(Diagnostics)>

local function sorted(entriesByOwner: { [string]: { Contracts.Diagnostic } }): { Contracts.Diagnostic }
	local entries: { Contracts.Diagnostic } = {}
	for _, ownedEntries in entriesByOwner do
		for _, diagnostic in ownedEntries do
			table.insert(entries, diagnostic)
		end
	end
	table.sort(entries, function(left: Contracts.Diagnostic, right: Contracts.Diagnostic): boolean
		if left.path ~= right.path then
			return left.path < right.path
		end
		if left.line ~= right.line then
			return left.line < right.line
		end
		if left.column ~= right.column then
			return left.column < right.column
		end
		if left.source ~= right.source then
			return (left.source or "") < (right.source or "")
		end
		return left.message < right.message
	end)
	return entries
end

function Diagnostics.new(onUpdate: (({ Contracts.Diagnostic }) -> ())?): Diagnostics
	local fields: Fields = { entriesByOwner = {}, onUpdate = onUpdate }
	return setmetatable(fields, Diagnostics)
end

function Diagnostics.Replace(self: Diagnostics, owner: string, entries: { Contracts.Diagnostic }): ()
	local ownedEntries: { Contracts.Diagnostic } = {}
	for _, diagnostic in entries do
		local copy: Contracts.Diagnostic = table.clone(diagnostic)
		copy.source = copy.source or owner
		table.insert(ownedEntries, copy)
	end
	self.entriesByOwner[owner] = ownedEntries
	if self.onUpdate then
		self.onUpdate(sorted(self.entriesByOwner))
	end
end

function Diagnostics.Snapshot(self: Diagnostics): { Contracts.Diagnostic }
	return sorted(self.entriesByOwner)
end

return Diagnostics
