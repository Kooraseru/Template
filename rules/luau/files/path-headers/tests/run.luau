-- rules/luau/files/path-headers/tests/run.luau
--!strict

local Fs = require("@std/fs")
local Runner = require("@ruleLinter/runner")

local root = "rules/luau/files/path-headers/tests/"
local valid = Fs.readFileToString(root .. "valid/header.luau"):gsub("\r\n", "\n")
local missing = Fs.readFileToString(root .. "invalid/missing.luau")
local mismatch = Fs.readFileToString(root .. "invalid/mismatch.luau")
local findings = Runner.Run({ "rules/luau/files/path-headers/validation.luau" }, {
	{ path = "source/header.luau", source = valid },
	{ path = "source/header.luau", source = valid:gsub("\n", "\r\n") },
	{ path = "source/missing.luau", source = missing },
	{ path = "source/mismatch.luau", source = mismatch },
	{ path = "source/tests/sample.luau", source = missing },
})
assert(#findings == 2)
assert(findings[1].path == "source/missing.luau")
assert(findings[2].path == "source/mismatch.luau")
for _, diagnostic in findings do
	local finding = diagnostic.finding
	assert(finding.severity == "error" and finding.line == 1 and finding.column == 1 and finding.endLine == 1)
end
assert(findings[1].finding.endColumn == 1, "Missing header should anchor at the insertion point")
local firstLine = assert(mismatch:match("^[^\r\n]*"))
assert(findings[2].finding.endColumn == #firstLine + 1, "Mismatched header should cover the full line")
print("Path-header fixtures passed")
