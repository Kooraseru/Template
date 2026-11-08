-- dependencies/packages/ruleLinter/editor.luau
--!strict

local Fs = require("@std/fs")
local Process = require("@lute/process")
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

local entries = Discovery.Discover()
if #entries == 0 then
	print("Repository rules: no validators discovered")
end
local function emit(file: string, rule: string, finding: Diagnostic.Finding, fixture: boolean, failure: ("fixture" | "checker")?)
	print("::rule-finding::" .. Json.encode({
		file = file, sourceHash = sourceHashes[file], source = if fixture then "Rule fixture" else rule, rule = rule, fixture = fixture,
		fixtureFailure = if failure == "fixture" then true else nil,
		checkerFailure = if failure == "checker" then true else nil,
		line = finding.line, column = finding.column, endLine = finding.endLine, endColumn = finding.endColumn,
		severity = finding.severity, message = finding.message, related = finding.related,
	}))
end
for _, entry in entries do
	local rule = entry:gsub("/validation/init%.luau$", ""):gsub("/validation%.luau$", "")
	local checked, diagnostics = pcall(Runner.Run, { entry }, sources)
	if checked then
		for _, diagnostic in diagnostics do
			emit(diagnostic.path, diagnostic.rule, diagnostic.finding, false)
		end
	else
		emit(entry, rule, {
			line = 1, column = 1, endLine = 1, endColumn = 1, severity = "error",
			message = "Checker failed: " .. tostring(diagnostics),
		}, false, "checker")
	end
	for _, category in { "valid", "invalid", "review" } do
		local directory = rule .. "/tests/" .. category
		if Fs.exists(directory) then
			local function collect(actualDirectory: string, virtualPrefix: string, fixtureSources: { Rule.Context }, fixtureFiles: { [string]: string })
				for _, file in Fs.listDirectory(actualDirectory) do
					local actualPath = actualDirectory .. "/" .. file.name
					local virtualPath = virtualPrefix .. "/" .. file.name
					if file.type == "dir" then
						collect(actualPath, virtualPath, fixtureSources, fixtureFiles)
					elseif file.name:match("%.luau$") then
						local source = Fs.readFileToString(actualPath)
						sourceHashes[actualPath] = Hash.sha256(source)
						fixtureFiles[virtualPath] = actualPath
						table.insert(fixtureSources, { path = virtualPath, source = source })
					end
				end
			end
			for _, testCase in Fs.listDirectory(directory) do
				local casePath = directory .. "/" .. testCase.name
				local caseVirtualPath = "source/" .. testCase.name
				local fixtureSources: { Rule.Context } = {}
				local fixtureFiles: { [string]: string } = {}
				if testCase.type == "dir" then
					collect(casePath, caseVirtualPath, fixtureSources, fixtureFiles)
				elseif testCase.name:match("%.luau$") then
					local source = Fs.readFileToString(casePath)
					sourceHashes[casePath] = Hash.sha256(source)
					local virtualPath = "source/" .. testCase.name
					fixtureFiles[virtualPath] = casePath
					table.insert(fixtureSources, { path = virtualPath, source = source })
				end
				if #fixtureSources == 0 then continue end
				local checked, findings = pcall(Runner.Run, { entry }, fixtureSources)
				local failure: string?
				if not checked then
					failure = "Fixture checker failed: " .. tostring(findings)
				elseif (#findings > 0) ~= (category == "invalid") then
					failure = "Unexpected " .. category .. " fixture result"
				end
				local failurePath = if testCase.type == "dir" then casePath .. "/init.luau" else casePath
				if failure then
					emit(failurePath, rule, { line = 1, column = 1, endLine = 1, endColumn = 1, severity = "error", message = failure }, false, "fixture")
					continue
				end
				for _, diagnostic in findings do
					local actualPath = fixtureFiles[diagnostic.path]
					if actualPath then emit(actualPath, rule, diagnostic.finding, true) end
				end
			end
		end
	end
end
