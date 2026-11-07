-- rules/languages/luau/files/path-headers/tests/run.luau
--!strict

local Fs = require("@std/fs")
local Linter = require("@ruleLinter")

local root = "rules/languages/luau/files/path-headers/tests/"
local valid = Fs.readFileToString(root .. "valid/header.luau"):gsub("\r\n", "\n")
local missing = Fs.readFileToString(root .. "invalid/missing.luau")
local mismatch = Fs.readFileToString(root .. "invalid/mismatch.luau")
local findings, count = Linter.Check({
	{ path = "source/sample.luau", source = valid },
	{ path = "source/sample.luau", source = valid:gsub("\n", "\r\n") },
	{ path = "source/missing.luau", source = missing },
	{ path = "source/mismatch.luau", source = mismatch },
	{ path = "source/tests/sample.luau", source = missing },
})
assert(count >= 1 and #findings == 2)
assert(findings[1].path == "source/missing.luau")
assert(findings[2].path == "source/mismatch.luau")
for _, diagnostic in findings do
	assert(diagnostic.finding.severity == "error" and diagnostic.finding.line == 1 and diagnostic.finding.column == 1)
end
print("Path-header fixtures passed")
