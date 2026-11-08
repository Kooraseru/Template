-- dependencies/packages/ruleLinter/editor.luau
--!strict

local Parser = require("@std/syntax/parser")
local Fs = require("@std/fs")
local Io = require("@std/io")
local Hash = require("@formats/hash")
local Json = require("@formats/json")
local Runner = require("@ruleLinter/runner")
local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")

type Variant = { index: number, settings: unknown }
type Entry = {
	id: string, directory: string, entry: string, readme: string,
	configurable: boolean, settings: unknown, variants: { Variant },
	settingsFor: { [string]: number },
}
type Request = { sources: { string }, entries: { Entry }, scoped: { source: string?, fixture: boolean? }? }

local request = Json.decode(Io.input()) :: Request
local sources: { Rule.Context } = {}
local sourceHashes: { [string]: string } = {}
for _, path in request.sources do
	local source = if request.scoped and request.scoped.source ~= nil then request.scoped.source else Fs.readFileToString(path)
	if request.scoped and not pcall(Parser.parseBlock, source) then
		print("::rule-incomplete::")
		return
	end
	sourceHashes[path] = Hash.sha256(source)
	table.insert(sources, { path = path, source = source })
end

if #request.entries == 0 then
	print("Repository rules: no validators discovered")
end
local function emit(file: string, rule: Entry, finding: Diagnostic.Finding, fixture: boolean, failure: ("fixture" | "checker")?)
	print("::rule-finding::" .. Json.encode({
		file = file, sourceHash = sourceHashes[file], source = if fixture then "Rule fixture" else rule.id,
		rule = rule.id, ruleDoc = rule.readme, fixture = fixture,
		fixtureFailure = if failure == "fixture" then true else nil,
		checkerFailure = if failure == "checker" then true else nil,
		line = finding.line, column = finding.column, endLine = finding.endLine, endColumn = finding.endColumn,
		severity = finding.severity, message = finding.message, related = finding.related,
	}))
end

local function checkerFailed(rule: Entry, failure: unknown)
	emit(rule.entry, rule, {
		line = 1, column = 1, endLine = 1, endColumn = 1, severity = "error",
		message = "Checker failed: " .. tostring(failure),
	}, false, "checker")
end

local function settingsFailed(rule: Entry, failure: unknown, index: number?)
	print("::rule-settings-error::" .. Json.encode({ rule = rule.id, message = tostring(failure), index = index }))
end

local prepared: { { rule: Entry, validators: { [number]: Rule.Rule } } } = {}
for _, rule in request.entries do
	local loaded, module = pcall(Runner.Load, rule.entry)
	if not loaded then
		checkerFailed(rule, module)
		continue
	end
	if rule.configurable and (type(module) ~= "table" or type((module :: { [string]: unknown }).Create) ~= "function") then
		checkerFailed(rule, "A rule with settings.json must export Create(settings)")
		continue
	end
	local configured, validator = pcall(Runner.Configure, module, rule.settings)
	if not configured then
		if rule.configurable then
			settingsFailed(rule, validator)
			return
		end
		checkerFailed(rule, validator)
		continue
	end
	local validators = { [0] = validator }
	for _, variant in rule.variants do
		local valid, scoped = pcall(Runner.Configure, module, variant.settings)
		if not valid then
			settingsFailed(rule, scoped, variant.index)
			return
		end
		validators[variant.index] = scoped
	end
	table.insert(prepared, { rule = rule, validators = validators })
end

for _, item in prepared do
	local rule, validators = item.rule, item.validators
	local grouped: { [number]: { Rule.Context } } = {}
	for _, source in sources do
		local index = rule.settingsFor[source.path] or 0
		local group = grouped[index]
		if not group then
			group = {}
			grouped[index] = group
		end
		table.insert(group, source)
	end
	for index, group in grouped do
		local checked, diagnostics = pcall(Runner.Check, validators[index], rule.id, group)
		if checked then
			for _, diagnostic in diagnostics do
				emit(diagnostic.path, rule, diagnostic.finding, false)
			end
		else
			checkerFailed(rule, diagnostics)
		end
	end
	if request.scoped and not request.scoped.fixture then continue end
	for _, category in { "valid", "invalid", "review" } do
		local directory = rule.directory .. "/tests/" .. category
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
				local checked, findings = pcall(Runner.Check, validators[0], rule.id, fixtureSources)
				local failure: string?
				if not checked then
					failure = "Fixture checker failed: " .. tostring(findings)
				elseif (#findings > 0) ~= (category == "invalid") then
					failure = "Unexpected " .. category .. " fixture result"
				end
				local failurePath = if testCase.type == "dir" and Fs.exists(casePath .. "/init.luau")
					then casePath .. "/init.luau" else fixtureFiles[fixtureSources[1].path]
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
