-- config/preflight/stylua/init.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Contracts = require("@ci/preflight/contracts")
local WorkspaceFiles = require("@ci/preflight/workspaceFiles")
local Serde = require("@lune/serde")

local StyluaProvider = {}
StyluaProvider.__index = StyluaProvider

type Fields = { configuration: Contracts.ProviderPackage }
type ToolResult = { ok: boolean, code: number, stdout: string, stderr: string }
type DiffMismatch = { expected_start_line: number, expected_end_line: number }
type DiffFile = { file: string, mismatches: { DiffMismatch }? }

export type StyluaProvider = setmetatable<Fields, typeof(StyluaProvider)>

local function diagnostic(
	path: string,
	line: number,
	endLine: number,
	message: string,
	severity: "error" | "warning" | "info"
): Contracts.Diagnostic
	return {
		path = path,
		line = line,
		column = 1,
		endColumn = endLine + 1,
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

local function locateBinary(): string?
	local configured = Process.env.PREFLIGHT_STYLUA_PATH
	if configured and Fs.isFile(configured) then
		return configured
	end
	local windows = Process.env.USERPROFILE ~= nil
	local command = if windows then "where.exe" else "which"
	local name = if windows then "stylua.exe" else "stylua"
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

	local storageRoot = Process.env.PREFLIGHT_VSCODE_GLOBAL_STORAGE
	local profile = Process.env.USERPROFILE or Process.env.HOME
	local extensionRoot = if storageRoot
		then `{storageRoot:gsub("\\", "/")}/johnnymorganz.stylua`
		else if profile
			then `{profile:gsub("\\", "/")}/AppData/Roaming/Code/User/globalStorage/johnnymorganz.stylua`
			else nil
	if extensionRoot then
		if Fs.isDir(extensionRoot) then
			local pending: { string } = { extensionRoot }
			local cursor = 1
			while cursor <= #pending do
				local directory = pending[cursor]
				cursor += 1
				if not directory then
					continue
				end
				for _, nameEntry in Fs.readDir(directory) do
					local path = `{directory}/{nameEntry}`
					if Fs.isDir(path) then
						table.insert(pending, path)
					elseif nameEntry:lower() == "stylua.exe" or nameEntry:lower() == "stylua" then
						return path
					end
				end
			end
		end
	end
	return nil
end

local function inputPatterns(configuration: Contracts.ProviderPackage): ({ string }?, string?)
	local configured = configuration.options.inputs
	if type(configured) ~= "table" then
		return nil, "inputs must be a TOML array of globs"
	end
	local patterns: { string } = {}
	for _, pattern in configured do
		if type(pattern) ~= "string" or pattern == "" then
			return nil, "inputs must contain nonempty glob strings"
		end
		table.insert(patterns, pattern)
	end
	return patterns, nil
end

function StyluaProvider.new(configuration: Contracts.ProviderPackage): StyluaProvider
	local fields: Fields = { configuration = configuration }
	return setmetatable(fields, StyluaProvider)
end

function StyluaProvider.Analyze(self: StyluaProvider, _context: Contracts.Context): Contracts.ProviderResult
	local configuration = self.configuration
	local executable = locateBinary()
	if not executable then
		return {
			diagnostics = {
				diagnostic(
					configuration.configPath,
					1,
					2,
					"StyLua executable was not found; formatting check was skipped",
					"warning"
				),
			},
		}
	end

	local patterns, patternError = inputPatterns(configuration)
	if not patterns then
		return {
			diagnostics = {
				diagnostic(configuration.configPath, 1, 2, patternError or "invalid input globs", "error"),
			},
		}
	end
	local files = WorkspaceFiles.Find(patterns)
	if #files == 0 then
		return { diagnostics = {} }
	end

	local styleConfig = configuration.options.settings
	if type(styleConfig) ~= "string" or not Fs.isFile(styleConfig) then
		return {
			diagnostics = {
				diagnostic(configuration.configPath, 1, 2, "configured StyLua settings file is missing", "error"),
			},
		}
	end

	local arguments: { string } = { "--check", "--config-path", styleConfig, "--output-format", "Json" }
	for _, file in files do
		table.insert(arguments, file)
	end
	local ran, result = xpcall(function(): ToolResult
		local process = Process.exec(executable, arguments, { cwd = Process.cwd })
		return { ok = process.ok, code = process.code, stdout = process.stdout, stderr = process.stderr }
	end, tostring)
	if not ran then
		return {
			diagnostics = { diagnostic(configuration.configPath, 1, 2, `StyLua failed to start: {result}`, "error") },
		}
	end
	if result.ok then
		return { diagnostics = {} }
	end

	local diagnostics: { Contracts.Diagnostic } = {}
	local output = `{result.stdout}\n{result.stderr}`
	local decoded, report = xpcall(function(): DiffFile
		return Serde.decode("json", result.stdout) :: DiffFile
	end, tostring)
	if decoded and type(report.mismatches) == "table" then
		local sourcePath = normalizedPath(report.file)
		for _, mismatch in report.mismatches or {} do
			local firstLine = mismatch.expected_start_line
			local lastLine = mismatch.expected_end_line
			local startLine = math.max(1, firstLine + 1)
			local finishLine = math.max(startLine, lastLine)
			local message =
				`StyLua formatting differs on lines {startLine}-{finishLine}; inspect this range for the configured style difference`
			local entry = diagnostic(sourcePath, startLine, finishLine, message, "warning")
			entry.endLine = finishLine
			table.insert(diagnostics, entry)
		end
	end
	if #diagnostics == 0 then
		local detail = output:match("[^\r\n]+") or `exit status {result.code}`
		table.insert(
			diagnostics,
			diagnostic(
				configuration.configPath,
				1,
				2,
				`StyLua check failed without a structured diff: {detail}`,
				"error"
			)
		)
	end
	return { diagnostics = diagnostics }
end

return StyluaProvider
