-- repo/ci/bootstrap/reporter.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local SkipPolicy = require("./skipPolicy")

local Reporter = {}
Reporter.__index = Reporter

type ReporterFields = {
	template: string,
}

export type Reporter = setmetatable<ReporterFields, typeof(Reporter)>

function Reporter.new(): Reporter
	local fields: ReporterFields = {
		template = Fs.readFile("repo/content/ci/bootstrap-summary.md"),
	}
	return setmetatable(fields, Reporter)
end

function Reporter.Report(self: Reporter, outcomes: { [string]: string }, selectedCount: number): ()
	local identities: { string } = {}
	for identity in outcomes do
		table.insert(identities, identity)
	end
	table.sort(identities)
	local rows: { string } = {}
	for _, identity in identities do
		local outcome = outcomes[identity]
		if outcome == "skipped" then
			outcome = if SkipPolicy.Reject(identity) then "skipped (policy: fail)" else "skipped (policy: allow)"
		end
		table.insert(rows, `| {identity} | {outcome} |`)
	end
	if #identities == 0 then
		table.insert(rows, "| — | No components were discovered |")
	end

	local text = self.template:gsub("{{selected_count}}", tostring(selectedCount))
	text = text:gsub("{{component_rows}}", table.concat(rows, "\n"))
	print(text)

	local destination = Process.env.GITHUB_STEP_SUMMARY
	if destination then
		local current = if Fs.isFile(destination) then Fs.readFile(destination) else ""
		Fs.writeFile(destination, `{current}{text}`)
	end
end

return Reporter
