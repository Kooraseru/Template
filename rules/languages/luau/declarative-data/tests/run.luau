-- rules/languages/luau/declarative-data/tests/run.luau
--!strict

local Fs = require("@std/fs")
local Validator = require("@workspace/rules/languages/luau/declarative-data/validation")

local root = "rules/languages/luau/declarative-data/tests"
local count = 0
for _, category in { "valid", "invalid", "review" } do
	for _, entry in Fs.listDirectory(root .. "/" .. category) do
		local name = entry.name
		local source = Fs.readFileToString(root .. "/" .. category .. "/" .. name)
		local findings = Validator:Check({ path = "source/" .. name, source = source })
		assert((#findings > 0) == (category == "invalid"), category .. "/" .. name)
		for _, finding in findings do
			assert(finding.severity == "error" and finding.line >= 1 and finding.column >= 1)
		end
		count += 1
	end
end
assert(count == 21)
print(`Declarative-data fixtures passed: {count}`)

local assigned = Validator:Check({ path = "source/assigned.luau", source = [[
local function componentTree(entries)
	local assigned: { [string]: boolean } = {}
	local function insert(node)
		assigned[node.component] = true
	end
	for _, node in entries do insert(node) end
	return assigned
end
return componentTree
]] })
assert(#assigned == 0, "runtime-mutated index must not be classified as static data")
