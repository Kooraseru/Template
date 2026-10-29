-- repo/ci/preflight/providers/luauLsp/init.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Contracts = require("@ci/preflight/contracts")
local WorkspaceFiles = require("@ci/preflight/workspaceFiles")

local LuauLspProvider = {}
LuauLspProvider.__index = LuauLspProvider

type Fields = { configuration: Contracts.ProviderPackage }
type ToolResult = { ok: boolean, code: number, stdout: string, stderr: string }

export type LuauLspProvider = setmetatable<Fields, typeof(LuauLspProvider)>

local function diagnostic(
	configuration: Contracts.ProviderPackage,
	path: string,
	message: string,
	severity: "error" | "warning" | "info"
): Contracts.Diagnostic
	return {
		path = path,
		line = 1,
		column = 1,
		endColumn = 2,
		severity = severity,
		message = message,
	}
end

local function normalizedPath(path: string): string
	local normalized = path:gsub("\\", "/")
	local workingDirectory = Process.cwd:gsub("\\", "/"):gsub("/+$", "")
	local prefix = `{workingDirectory}/`
	if normalized:sub(1, #prefix):lower() == prefix:lower() then
		return normalized:sub(#prefix + 1)
	end
	return normalized
end

local function extensionBinary(): string?
	local profile = Process.env.USERPROFILE or Process.env.HOME
	if not profile then
		return nil
	end
	local extensionRoot = `{profile:gsub("\\", "/")}/.vscode/extensions`
	if not Fs.isDir(extensionRoot) then
		return nil
	end
	for _, extension in Fs.readDir(extensionRoot) do
		if extension:match("^johnnymorganz%.luau%-lsp%-") then
			local server = `{extensionRoot}/{extension}/bin/server.exe`
			if Fs.isFile(server) then
				return server
			end
		end
	end
	return nil
end

local function locateBinary(): string?
	local configured = Process.env.PREFLIGHT_LUAU_LSP
	if configured and Fs.isFile(configured) then
		return configured
	end
	local windows = Process.env.USERPROFILE ~= nil
	local command = if windows then "where.exe" else "which"
	local name = if windows then "luau-lsp.exe" else "luau-lsp"
	local found, result = xpcall(function(): ToolResult
		local process = Process.exec(command, { name })
		return { ok = process.ok, code = process.code, stdout = process.stdout, stderr = process.stderr }
	end, tostring)
	if found and result.ok then
		local binary = result.stdout:match("([^\r\n]+)")
		if binary then
			local cleanBinary = binary:gsub("\r", "")
			return cleanBinary
		end
	end
	return extensionBinary()
end

local function patterns(configuration: Contracts.ProviderPackage): ({ string }?, string?)
	local configured = configuration.options.inputs
	if type(configured) ~= "table" then
		return nil, "inputs must be a TOML array of globs"
	end
	local result: { string } = {}
	for _, pattern in configured do
		if type(pattern) ~= "string" or pattern == "" then
			return nil, "inputs must contain nonempty glob strings"
		end
		table.insert(result, pattern)
	end
	return result, nil
end

local function parseDiagnostic(line: string): Contracts.Diagnostic?
	local path, lineNumber, column, _, endColumn, code, message =
		line:match("^(.-):(%d+)%.(%d+)%-(%d+)%.(%d+):%s*([^:]+):%s*(.*)$")
	if not path or not lineNumber or not column or not endColumn or not code or not message then
		return nil
	end
	local startColumn = tonumber(column)
	local finishColumn = tonumber(endColumn)
	local lineIndex = tonumber(lineNumber)
	if not startColumn or not finishColumn or not lineIndex then
		return nil
	end
	return {
		path = normalizedPath(path),
		line = lineIndex,
		column = startColumn,
		endColumn = math.max(startColumn + 1, finishColumn),
		severity = if code == "TypeError" or code == "SyntaxError" then "error" else "warning",
		message = `{code}: {message}`,
	}
end

function LuauLspProvider.new(configuration: Contracts.ProviderPackage): LuauLspProvider
	local fields: Fields = { configuration = configuration }
	return setmetatable(fields, LuauLspProvider)
end

function LuauLspProvider.Analyze(self: LuauLspProvider, _context: Contracts.Context): Contracts.ProviderResult
	local configuration = self.configuration
	local executable = locateBinary()
	if not executable then
		return {
			diagnostics = {
				diagnostic(
					configuration,
					configuration.configPath,
					"luau-lsp analyzer executable was not found",
					"warning"
				),
			},
		}
	end

	local inputPatterns, patternError = patterns(configuration)
	if not inputPatterns then
		return {
			diagnostics = {
				diagnostic(configuration, configuration.configPath, patternError or "invalid input globs", "error"),
			},
		}
	end
	local files = WorkspaceFiles.Find(inputPatterns)
	if #files == 0 then
		return { diagnostics = {} }
	end

	local settings = configuration.options.settings
	local luaurc = configuration.options.luaurc
	local platform = configuration.options.platform
	if type(settings) ~= "string" or type(luaurc) ~= "string" or type(platform) ~= "string" then
		return {
			diagnostics = {
				diagnostic(
					configuration,
					configuration.configPath,
					"settings, luaurc, and platform must be strings",
					"error"
				),
			},
		}
	end
	if not Fs.isFile(settings) or not Fs.isFile(luaurc) then
		return {
			diagnostics = {
				diagnostic(
					configuration,
					configuration.configPath,
					"configured Luau LSP settings or luaurc file is missing",
					"error"
				),
			},
		}
	end

	local arguments: { string } = {
		"analyze",
		"--formatter=gnu",
		"--settings",
		settings,
		"--base-luaurc",
		luaurc,
		"--platform",
		platform,
	}
	for _, path in files do
		table.insert(arguments, path)
	end

	local ran, result = xpcall(function(): ToolResult
		local process = Process.exec(executable, arguments, { cwd = Process.cwd })
		return { ok = process.ok, code = process.code, stdout = process.stdout, stderr = process.stderr }
	end, tostring)
	if not ran then
		return {
			diagnostics = {
				diagnostic(configuration, configuration.configPath, `luau-lsp failed to start: {result}`, "error"),
			},
		}
	end

	local diagnostics: { Contracts.Diagnostic } = {}
	local output = `{result.stdout}\n{result.stderr}`
	for line in output:gmatch("[^\r\n]+") do
		local parsed = parseDiagnostic(line)
		if parsed then
			table.insert(diagnostics, parsed)
		end
	end
	if not result.ok and #diagnostics == 0 then
		local detail = output:match("[^\r\n]+") or `exit status {result.code}`
		table.insert(
			diagnostics,
			diagnostic(
				configuration,
				configuration.configPath,
				`luau-lsp returned no parseable diagnostics: {detail}`,
				"error"
			)
		)
	end
	return { diagnostics = diagnostics }
end

return LuauLspProvider
