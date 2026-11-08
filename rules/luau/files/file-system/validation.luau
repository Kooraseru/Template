-- rules/luau/files/file-system/validation.luau
--!strict

local Comments = require("@ruleLinter/comments")
local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")

local function loadMarkerPolicy(settings: unknown): ({ [string]: boolean }, { [string]: boolean })
	if type(settings) ~= "table" then
		error("File-system rule settings must be an object", 0)
	end
	local sectionMarkers = (settings :: { [string]: unknown }).sectionMarkers
	if type(sectionMarkers) ~= "table" then
		error("File-system rule settings must define sectionMarkers", 0)
	end
	local policy = sectionMarkers :: { [string]: unknown }
	local function readNames(field: string): { [string]: boolean }
		local value = policy[field]
		if type(value) ~= "table" then
			error(`File-system sectionMarkers.{field} must be an array`, 0)
		end
		local names: { [string]: boolean } = {}
		for _, name in (value :: { unknown }) do
			if type(name) ~= "string" or name == "" or name:match("^%s*$") then
				error(`File-system sectionMarkers.{field} must contain nonempty names`, 0)
			end
			if names[name] then
				error(`Duplicate section marker '{name}' in sectionMarkers.{field}`, 0)
			end
			names[name] = true
		end
		return names
	end
	local allowed = readNames("allowed")
	local disallowed = readNames("disallowed")
	for name in allowed do
		if disallowed[name] then
			error(`Section marker '{name}' cannot be both allowed and disallowed`, 0)
		end
	end
	return allowed, disallowed
end

local function create(settings: unknown): Rule.Rule
	local allowedMarkers, disallowedMarkers = loadMarkerPolicy(settings)

	return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
		local path = context.path:gsub("\\", "/")
		if not path:match("%.luau$") then
			return {}
		end
		for segment in path:gmatch("[^/]+") do
			if segment == "generated" or segment == "vendor" or segment == "examples" or segment == "tests" then
				return {}
			end
		end
		local first, second = context.source:match("^([^\r\n]*)\r?\n?([^\r\n]*)")
		local findings: { Diagnostic.Finding } = {}
		local hasPathHeader = first and first:match("^%-%- .+%.luau$")
		if first ~= "--!strict" and not (hasPathHeader and second == "--!strict") then
			local line = if hasPathHeader then 2 else 1
			local header = if line == 2 then second else first
			local width = if header and header:match("^%-%-!") then #header else 0
			findings[#findings + 1] = {
				line = line, column = 1, endLine = line, endColumn = width + 1,
				severity = "warning", message = "Declare --!strict at the top of hand-written Luau source.",
			}
		end
		local lines = context.source:split("\n")
		Comments.VisitLineComments(context.source, function(comment, span)
			local header = comment:match("^%-%-#%s*(.-)%s*$")
			if not header or not lines[span.beginLine]:sub(1, span.beginColumn - 1):match("^%s*$") then
				return
			end
			if allowedMarkers[header] then
				return
			end
			local message = if disallowedMarkers[header]
				then `Section marker '--# {header}' is explicitly disallowed. Remove it or update the section-marker policy.`
				else `Section marker '--# {header}' is not approved. Add it to the allowed list or remove it.`
			findings[#findings + 1] = {
				line = span.beginLine, column = span.beginColumn,
				endLine = span.endLine, endColumn = span.endColumn,
				severity = "warning", message = message,
			}
		end)
		return findings
	end)
end

return { Create = create }
