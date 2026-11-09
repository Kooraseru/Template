-- rules/luau/design/script-layout/tests/run.luau
--!strict

local Fs = require("@std/fs")
local Parser = require("@std/syntax/parser")
local Layout = require("@workspace/rules/luau/design/script-layout/validation")
local Documentation = require("@workspace/rules/luau/style/function-documentation/validation")
local Phases = require("@workspace/rules/luau/style/phase-comments/validation")

local root = "rules/luau/design/script-layout/"
local layout = Layout.Create({
	entryPoints = { "source/start.luau" },
	ecsComponents = { "source/position.luau" },
	ecsSystems = { "source/movement.luau" },
})

local starters: { [string]: string } = {
	["function-module"] = "source/function.luau",
	["table-module"] = "source/module.luau",
	object = "source/object.luau",
	["entry-point"] = "source/start.luau",
	["ecs-component"] = "source/position.luau",
	["ecs-system"] = "source/movement.luau",
}

for name, path in starters do
	local source = Fs.readFileToString(root .. "examples/" .. name .. ".luau")
	Parser.parse(source)
	assert(#layout:Check({ path = path, source = source }) == 0, name)
	local marker = assert(source:match("%-%-# [^\r\n]+"))
	local findings = layout:Check({ path = path, source = source .. "\n" .. marker .. "\n" })
	assert(#findings == 1 and findings[1].message:find("appears more than once", 1, true), name)
end

local method = Fs.readFileToString(root .. "tests/invalid/method-in-constants.luau")
local misplaced = layout:Check({ path = "source/object.luau", source = method })
assert(#misplaced == 1 and misplaced[1].message:find("to Methods", 1, true))
local ecs = layout:Check({ path = "source/position.luau", source = "--# Methods\nreturn true\n" })
assert(#ecs == 1 and ecs[1].message:find("ecs-component", 1, true))
local outOfOrder = layout:Check({ path = "source/function.luau", source = "--# Functions\n--# Types\nreturn function() end\n" })
assert(outOfOrder[1].message:find("out of order", 1, true) ~= nil)
assert(#layout:Check({ path = "source/function.luau", source = "--# Constants\nreturn function(" }) == 0)

local helper = "local function read() return true end\nreturn read\n"
assert(#Documentation:Check({ path = "source/helper.luau", source = helper }) == 1)
assert(#Documentation:Check({ path = "source/helper.luau", source = "--- Read the current readiness state.\n" .. helper }) == 0)

local nested = "--- Check readiness.\nlocal function outer()\n local function inner() return true end\n return inner()\nend\nreturn outer"
assert(#Documentation:Check({ path = "source/helper.luau", source = nested }) == 0)

local phaseRoot = "rules/luau/style/phase-comments/tests/"
local unexplained = Fs.readFileToString(phaseRoot .. "invalid/unexplained-workflow.luau")
local explained = Fs.readFileToString(phaseRoot .. "valid/explained-workflow.luau")
local twoPhases = unexplained:gsub("\t%-%- Report a neutral spread for an empty input%.\r?\n", "")
local findings = Phases:Check({ path = "source/metrics.luau", source = twoPhases })
assert(#findings == 2)
for _, finding in findings do
	assert(finding.line == finding.endLine)
end
assert(#Phases:Check({ path = "source/metrics.luau", source = explained }) == 0)

local contract = "ci/bootstrap/contracts/contract.luau"
local source = Fs.readFileToString(contract)
assert(#layout:Check({ path = contract, source = source }) == 0)
assert(#Documentation:Check({ path = contract, source = source }) == 0)
print("Script layout and comment regressions passed.")
