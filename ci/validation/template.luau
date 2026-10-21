-- ci/validation/template.luau
--!strict

local Template = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Stdio = require("@lune/stdio")
local Rules = require("../libraries/registry/rules")
local Policy = require("./policy")
local Workflows = require("./workflows")
local Project = require("../fabricator/project")
local Config = require("../libraries/registry/config")
local Canonical = require("../libraries/bootstrap/canonical")

--# Types

export type Finding = { Path: string, Message: string }
export type Reader = (string) -> string

--# Helpers

local function safePath(path: string): string
	path = path:gsub("^%./", "")
	assert(path ~= "" and not path:find("\\", 1, true) and path:sub(1, 1) ~= "/", "invalid repository path")
	for component in path:gmatch("[^/]+") do
		assert(component ~= ".." and not component:find(":", 1, true), "path escapes repository")
	end
	return path
end

local function escape(text: string): string
	return (text:gsub("%%", "%%25"):gsub("\r", "%%0D"):gsub("\n", "%%0A"))
end

--# Functions

function Template.Check(read: Reader, files: { string }): { Finding }
	local contract =
		Rules.Entries(Rules.Property(Serde.decode("json", Fs.readFile("ci/validation/ruleset.json")), "template"))
	local inventory: { [string]: boolean } = {}
	local findings: { Finding } = {}

	for _, path in files do
		inventory[safePath(path)] = true
	end

	local function check(path: string, operation: () -> ())
		local ok, message = pcall(operation)
		if not ok then
			table.insert(findings, { Path = path, Message = tostring(message) })
		end
	end

	local roots = Rules.Array(contract.root_directories)
	local reported: { [string]: boolean } = {}
	for path in inventory do
		local root = path:match("^([^/]+)/")
		if root and root:sub(1, 1) ~= "." and not table.find(roots, root) and not reported[root] then
			reported[root] = true
			table.insert(findings, {
				Path = root,
				Message = "Place authored code and dependencies under src/, or infrastructure under its owning template subsystem.",
			})
		end
	end

	for _, value in Rules.Array(contract.required) do
		local path = tostring(value)
		local present = inventory[path] == true
		for file in inventory do
			present = present or file:sub(1, #path + 1) == path .. "/"
		end
		if not present then
			table.insert(
				findings,
				{ Path = path, Message = "Restore the required template responsibility at this path." }
			)
		end
	end

	for _, raw in Rules.Array(contract.documents) do
		local document = Rules.Entries(raw)
		local path = tostring(document.path)
		check(path, function()
			local data = Serde.decode(tostring(document.format) :: "yaml", read(path))
			local definitions = Rules.Read("ci/validation/ruleset.json", tostring(document.rules))
			Rules.Validate(data, definitions)
			Workflows.CheckBoundaries(data)
			Workflows.CheckActions(data, assert(definitions.actions), function(actionPath)
				return Serde.decode("yaml", read(safePath(actionPath)))
			end)
		end)
	end

	check("config/project.toml", function()
		local repository = Serde.decode("toml", read("config/project.toml"))
		local source = if inventory["src/build.toml"] then Serde.decode("toml", read("src/build.toml")) else {}
		Config.Validate(Project.Combine(repository, source))
	end)

	check(".gitignore", function()
		assert(read(".gitignore"):find("/build/", 1, true), "Ignore disposable /build/ output.")
		for path in inventory do
			assert(path:sub(1, 6) ~= "build/", "Remove tracked disposable build output: " .. path)
		end
	end)

	local policy = Policy.Read()
	for _, path in files do
		if path:sub(-5) ~= ".luau" then
			continue
		end
		local selected = false
		for _, root in Rules.Array(contract.module_roots) do
			local prefix = tostring(root)
			selected = selected or path:sub(1, #prefix) == prefix
		end
		if selected then
			check(path, function()
				local errors = Policy.CheckModule(read(path), path, policy)
				assert(#errors == 0, table.concat(errors, "; "))
			end)
		end
	end

	table.sort(findings, function(a: Finding, b: Finding)
		return a.Path < b.Path
	end)
	return findings
end

function Template.Run()
	local root = assert(Process.args[1], "expected downstream checkout path")
	local upstream = assert(Process.args[2], "expected examined upstream commit")
	local destination = Process.env.TEMPLATE_REPORT or "build/template-conformance.json"
	local listed = Process.exec("git", { "-C", root, "ls-files", "--stage", "-z" })
	assert(listed.ok, "cannot inventory downstream checkout")
	local files: { string } = {}
	local regular: { [string]: boolean } = {}

	for entry in listed.stdout:gmatch("[^%z]+") do
		local mode, path = entry:match("^(%d+) %x+ %d+\t(.+)$")
		assert(mode and path, "invalid tracked-file inventory")
		table.insert(files, path)
		regular[path] = mode == "100644" or mode == "100755"
	end

	local findings = Template.Check(function(path)
		path = safePath(path)
		assert(regular[path], "Expected a tracked regular file: " .. path)
		local bytes = Fs.readFile(root .. "/" .. path)
		assert(#bytes <= 1024 * 1024, "Infrastructure file exceeds inspection limit: " .. path)
		return bytes
	end, files)
	local report = {
		status = if #findings == 0 then "conforms" else "drift_detected",
		upstream_commit = upstream,
		findings = findings,
	}
	local rows: { Canonical.Value } = {}
	for _, finding in findings do
		table.insert(rows, Canonical.FromLune(finding))
	end
	Fs.writeFile(destination, assert(Canonical.Encode(Canonical.Object({
		status = report.status,
		upstream_commit = upstream,
		findings = Canonical.Array(rows),
	}))) .. "\n")
	local summary = "# Template conformance\n\nResult: **"
		.. report.status
		.. "**\n\nExamined upstream commit: `"
		.. upstream
		.. "`\n"
	for _, finding in findings do
		summary ..= "\n- `" .. finding.Path:gsub("`", "") .. "`: " .. finding.Message:gsub("[\r\n]", " ")
		Stdio.write("::error title=Template drift::" .. escape(finding.Path .. ": " .. finding.Message) .. "\n")
	end
	local summaryPath = Process.env.GITHUB_STEP_SUMMARY
	if summaryPath then
		Fs.writeFile(summaryPath, summary .. "\n")
	end
	assert(#findings == 0, "Template drift detected; inspect the conformance report.")
end

return Template
