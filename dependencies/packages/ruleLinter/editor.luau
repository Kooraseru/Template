-- dependencies/packages/ruleLinter/editor.luau
--!strict

local Fs = require("@std/fs")
local Process = require("@lute/process")
local Linter = require("@ruleLinter")
local Hash = require("@formats/hash")
local Json = require("@formats/json")
local Discovery = require("@ruleLinter/discovery")
local Runner = require("@ruleLinter/runner")
local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")

local sources: { Rule.Context } = {}
local sourceHashes: { [string]: string } = {}
for index = 2, #Process.args do
	local path = Process.args[index]
	local source = Fs.readFileToString(path)
	sourceHashes[path] = Hash.sha256(source)
	table.insert(sources, { path = path, source = source })
end

local diagnostics, count = Linter.Check(sources)
if count == 0 then
	print("Repository rules: no validators discovered")
end
local function emit(file: string, rule: string, finding: Diagnostic.Finding, fixture: boolean, fixtureFailure: boolean?)
	print("::rule-finding::" .. Json.encode({
		file = file, sourceHash = sourceHashes[file], source = if fixture then "Rule fixture" else rule, rule = rule, fixture = fixture, fixtureFailure = fixtureFailure,
		line = finding.line, column = finding.column, endLine = finding.endLine, endColumn = finding.endColumn,
		severity = finding.severity, message = finding.message, related = finding.related,
	}))
end
for _, diagnostic in diagnostics do
	emit(diagnostic.path, diagnostic.rule, diagnostic.finding, false)
end
for _, entry in Discovery.Discover() do
	local rule = entry:gsub("/validation/init%.luau$", ""):gsub("/validation%.luau$", "")
	for _, category in { "valid", "invalid", "review" } do
		local directory = rule .. "/tests/" .. category
		if Fs.exists(directory) then
			for _, file in Fs.listDirectory(directory) do
				if not file.name:match("%.luau$") then continue end
				local fixture = directory .. "/" .. file.name
				local source = Fs.readFileToString(fixture)
				sourceHashes[fixture] = Hash.sha256(source)
				local findings = Runner.Run({ entry }, {{ path = "source/sample.luau", source = source }})
				if (#findings > 0) ~= (category == "invalid") then
					emit(fixture, rule, { line = 1, column = 1, endLine = 1, endColumn = 1, severity = "error", message = "Unexpected " .. category .. " fixture result" }, false, true)
				else
					for _, diagnostic in findings do emit(fixture, rule, diagnostic.finding, true) end
				end
			end
		end
	end
end
