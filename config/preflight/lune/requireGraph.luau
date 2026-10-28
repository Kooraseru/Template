-- config/preflight/lune/requireGraph.luau
--!strict

-- Trace source imports from the CI entry and generated component plan.
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")

local Contract = require("@ci/bootstrap/contract")
local Glob = require("@ci/bootstrap/glob")
local Contracts = require("@ci/preflight/contracts")
local Graph = require("./graph")
local SourceScanner = require("./sourceScanner")

local Analyzer = {}
Analyzer.__index = Analyzer

export type Diagnostic = Contracts.Diagnostic

export type Result = {
	diagnostics: { Diagnostic },
	passed: boolean,
	reachable: { [string]: { string } },
}

type Fields = {
	scanner: SourceScanner.SourceScanner,
	aliases: { [string]: string },
}

export type Analyzer = setmetatable<Fields, typeof(Analyzer)>

local function segments(path: string): { string }
	local result: { string } = {}
	for segment in path:gmatch("[^/]+") do
		if segment == ".." then
			if #result == 0 then
				return {}
			end
			table.remove(result)
		elseif segment ~= "." and segment ~= "" then
			table.insert(result, segment)
		end
	end
	return result
end

local function normalized(path: string): string?
	local parts = segments(path)
	if #parts == 0 and path ~= "" then
		return nil
	end
	return table.concat(parts, "/")
end

local function directory(path: string): string
	return path:match("^(.*)/[^/]+$") or ""
end

local function relativeBase(path: string): string
	local parent = directory(path)
	if path:match("/init%.luau$") or path:match("/init%.lua$") then
		return directory(parent)
	end
	return parent
end

local function contractValueLocation(path: string, field: string, value: string): (number?, number?, number?)
	local inField = false
	local lineNumber = 0
	local source = Fs.readFile(path):gsub("\r\n", "\n")
	for line in (source .. "\n"):gmatch("(.-)\n") do
		lineNumber += 1
		if not inField and line:match("^%s*" .. field .. "%s*=%s*%[") then
			inField = true
		end
		if inField then
			local literalStart = line:find('"' .. value .. '"', 1, true) or line:find("'" .. value .. "'", 1, true)
			if literalStart then
				local column = literalStart + 1
				return lineNumber, column, column + #value
			end
			if line:find("]", 1, true) then
				inField = false
			end
		end
	end
	return nil, nil, nil
end

local function candidates(path: string): { string }
	if path:match("%.luau$") or path:match("%.lua$") then
		return { path }
	end
	return { `{path}.luau`, `{path}.lua`, `{path}/init.luau`, `{path}/init.lua` }
end

function Analyzer.new(): Analyzer
	local configuration = Serde.decode("json", Fs.readFile(".luaurc"))
	local aliases: { [string]: string } = {}
	if type(configuration) == "table" and type(configuration.aliases) == "table" then
		for name, value in configuration.aliases do
			if type(name) == "string" and type(value) == "string" and value:sub(1, 1) ~= "~" then
				local path = normalized(if value == "." then "" else value)
				if path then
					aliases[name] = path
				end
			end
		end
	end
	local fields: Fields = { scanner = SourceScanner.new(), aliases = aliases }
	return setmetatable(fields, Analyzer)
end

function Analyzer.ResolveModule(self: Analyzer, from: string, modulePath: string): string?
	if modulePath:match("^@lune/") then
		return `@lune/{modulePath:gsub("^@lune/", "")}`
	end

	local base: string
	local suffix: string
	local selfAlias = modulePath:match("^@self/(.+)$")
	local namedAlias, aliasSuffix = modulePath:match("^@([%w_-]+)/(.+)$")
	if selfAlias then
		base = directory(from)
		suffix = selfAlias
	elseif namedAlias and aliasSuffix and self.aliases[namedAlias] then
		base = self.aliases[namedAlias]
		suffix = aliasSuffix
	elseif modulePath:sub(1, 1) == "@" then
		return nil
	else
		base = relativeBase(from)
		suffix = modulePath
	end

	local combined = normalized(`{base}/{suffix}`)
	if not combined then
		return nil
	end
	for _, candidate in candidates(combined) do
		if Fs.isFile(candidate) and Fs.metadata(candidate).kind ~= "symlink" then
			return candidate
		end
	end
	return nil
end

function Analyzer.Analyze(self: Analyzer, tasks: { Contract.Task }): Result
	local graph = Graph.new()
	local diagnostics: { Diagnostic } = {}
	local expanded: { [string]: boolean } = {}
	local plannedEntries: { [string]: boolean } = {}
	local declaredScripts: { [string]: string } = {}

	local function report(
		path: string,
		line: number,
		column: number,
		severity: "error" | "warning" | "info",
		message: string,
		endColumn: number?,
		endLine: number?
	)
		for _, existing in diagnostics do
			if
				existing.path == path
				and existing.line == line
				and existing.column == column
				and existing.message == message
			then
				return
			end
		end
		local diagnostic: Diagnostic = {
			path = path,
			line = line,
			column = column,
			endColumn = endColumn or column + 1,
			severity = severity,
			message = message,
			endLine = endLine,
		}
		table.insert(diagnostics, diagnostic)
	end

	local function traceInformation(trace: { string }): { Contracts.RelatedInformation }
		local related: { Contracts.RelatedInformation } = {}
		for index = 1, #trace - 1 do
			local from = trace[index]
			local target = trace[index + 1]
			if not from or not target or not Fs.isFile(from) then
				continue
			end
			local line = 1
			local column = 1
			for _, link in self.scanner:Read(from).links do
				if link.path and self:ResolveModule(from, link.path) == target then
					line = link.line
					column = link.column
					break
				end
			end
			local targetLabel = target:gsub("%.luau$", ""):gsub("%.lua$", "")
			table.insert(related, {
				path = from,
				line = line,
				column = column,
				message = `Calls {targetLabel}`,
			})
		end
		return related
	end

	graph:AddNode("ci/entry.luau")
	for _, task in tasks do
		plannedEntries[task.entry] = true
		graph:AddEdge("ci/bootstrap/executor.luau", task.invoker, "planned invocation")
		graph:AddEdge(task.invoker, task.entry, "planned component entry")
		for _, inputPattern in task.inputs do
			local line, column, endColumn = contractValueLocation(task.contractFile, "inputs", inputPattern)
			line = line or 1
			column = column or 1
			local ok, matches = xpcall(Glob.Find, tostring, inputPattern)
			if not ok then
				report(
					task.contractFile,
					line,
					column,
					"error",
					`invalid input glob {inputPattern}: {matches}`,
					endColumn
				)
			elseif #matches == 0 then
				report(
					task.contractFile,
					line,
					column,
					"error",
					`declared input glob matches no files: {inputPattern}`,
					endColumn
				)
			else
				local fileMatches = 0
				for _, path in matches do
					local metadata = Fs.metadata(path)
					if metadata.kind == "dir" then
						continue
					end
					if metadata.kind ~= "file" then
						report(
							task.contractFile,
							line,
							column,
							"error",
							`declared input is not a regular file: {path}`,
							endColumn
						)
						continue
					end
					fileMatches += 1
					if path:match("%.luau$") or path:match("%.lua$") then
						declaredScripts[path] = task.identity
					end
				end
				if fileMatches == 0 then
					report(
						task.contractFile,
						line,
						column,
						"error",
						`declared input glob matches no files: {inputPattern}`,
						endColumn
					)
				end
			end
		end
		if not Fs.isFile(task.invoker) then
			report(task.entry, 1, 1, "error", `planned invoker does not exist: {task.invoker}`)
		end
		if not Fs.isFile(task.entry) then
			report(task.entry, 1, 1, "error", "planned component entry does not exist")
		end
	end

	local pending: { string } = { "ci/entry.luau" }
	for _, task in tasks do
		table.insert(pending, task.invoker)
		table.insert(pending, task.entry)
	end
	local cursor = 1
	while cursor <= #pending do
		local pendingPath = pending[cursor]
		cursor += 1
		if not pendingPath then
			continue
		end
		local path = normalized(pendingPath)
		if not path then
			continue
		end
		if expanded[path] or not Fs.isFile(path) then
			continue
		end
		expanded[path] = true
		local scan = self.scanner:Read(path)
		if path:match("^source/") or path:match("^ci/components/") then
			local foundCommands: { [string]: boolean } = {}
			for _, call in scan.runtimeCommands do
				local command = call.command or "dynamic executable"
				if not foundCommands[command] then
					foundCommands[command] = true
					report(
						path,
						call.line,
						call.column,
						"info",
						`external command '{command}' is reachable; its availability and result depend on runtime conditions`,
						call.endColumn,
						call.endLine
					)
				end
			end
		end
		for _, link in scan.links do
			if link.path then
				local resolved = self:ResolveModule(path, link.path)
				if not resolved then
					report(path, link.line, link.column, "error", `unresolved module reference: {link.path}`)
				else
					graph:AddEdge(path, resolved, "require")
					if not resolved:match("^@lune/") then
						table.insert(pending, resolved)
					end
				end
			elseif #scan.globs == 1 then
				local globOk, matches = xpcall(Glob.Find, tostring, scan.globs[1])
				if not globOk then
					report(path, link.line, link.column, "error", `dynamic discovery glob is invalid: {matches}`)
				elseif #matches == 0 then
					report(
						path,
						link.line,
						link.column,
						"error",
						`dynamic require has no discovered modules: {scan.globs[1]}`
					)
				else
					local discoveredModules = 0
					for _, match in matches do
						local target = if Fs.isDir(match) then `{match}/init.luau` else match
						if (target:match("%.luau$") or target:match("%.lua$")) and Fs.isFile(target) then
							discoveredModules += 1
							graph:AddEdge(path, target, "discovered require")
							table.insert(pending, target)
						end
					end
					if discoveredModules == 0 then
						report(
							path,
							link.line,
							link.column,
							"error",
							`dynamic require discovered no module files: {scan.globs[1]}`
						)
					end
				end
			elseif path == "ci/bootstrap/invoke.luau" then
				for entry in plannedEntries do
					graph:AddEdge(path, entry, "planned dynamic require")
					table.insert(pending, entry)
				end
			else
				report(path, link.line, link.column, "info", "dynamic module path cannot be proven statically")
			end
		end
	end

	for _, task in tasks do
		for _, dependency in task.needs do
			local provider: string? = nil
			for _, candidate in tasks do
				if candidate.identity == dependency then
					provider = candidate.entry
					break
				end
			end
			if provider then
				graph:AddEdge(provider, task.entry, "required component")
			else
				report(task.entry, 1, 1, "error", `planned dependency is missing: {dependency}`)
			end
		end
	end

	local reachable = graph:Reachable({ "ci/entry.luau" })
	for _, task in tasks do
		if not reachable[task.entry] then
			report(task.entry, 1, 1, "error", "planned component entry is unreachable from ci/entry.luau")
		end
	end
	for path, identity in declaredScripts do
		if not reachable[path] then
			report(
				path,
				1,
				1,
				"info",
				`{identity}: declared Luau input is not reachable through the planned module graph`
			)
		end
	end
	for _, diagnostic in diagnostics do
		local trace = reachable[diagnostic.path]
		if trace then
			diagnostic.relatedInformation = traceInformation(trace)
			if #trace > 1 then
				diagnostic.message = `Static execution path: {diagnostic.message}`
			end
		end
	end
	table.sort(diagnostics, function(left: Diagnostic, right: Diagnostic): boolean
		if left.path ~= right.path then
			return left.path < right.path
		end
		if left.line ~= right.line then
			return left.line < right.line
		end
		return left.column < right.column
	end)

	local passed = true
	for _, diagnostic in diagnostics do
		if diagnostic.severity == "error" then
			passed = false
		end
	end
	return { diagnostics = diagnostics, passed = passed, reachable = reachable }
end

return Analyzer
