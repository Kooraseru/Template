-- ci/content/tagRenderer.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Glob = require("@ci/bootstrap/glob")

const LOCALE_ROOT = "content/locales"

type Fields = { locale: string }

export type MissingTranslation = {
	path: string,
	line: number,
	column: number,
	endColumn: number,
	locale: string,
	tag: string,
	templatePath: string,
	templateLine: number,
}

export type MalformedTag = {
	path: string,
	line: number,
	column: number,
	endColumn: number,
	token: string,
}

local TagRenderer = {}
TagRenderer.__index = TagRenderer

export type TagRenderer = setmetatable<Fields, typeof(TagRenderer)>

local function readPageTags(locale: string, source: string): { [string]: string }
	local relative = source:gsub("^content/", ""):gsub("%.md$", ".toml")
	local path = `{LOCALE_ROOT}/{locale}/{relative}`
	if not Fs.isFile(path) or Fs.metadata(path).kind == "symlink" then
		return {}
	end
	local configuration = Serde.decode("toml", Fs.readFile(path))
	if type(configuration) ~= "table" or type(configuration.tags) ~= "table" then
		error(`{path}: expected a [tags] table`, 0)
	end
	local tags: { [string]: string } = {}
	for name, value in configuration.tags do
		if type(name) ~= "string" or type(value) ~= "string" then
			error(`{path}: tag names and values must be strings`, 0)
		end
		tags[name] = value
	end
	return tags
end

local function localeNames(): { string }
	local found: { string } = {}
	for _, path in Glob.Find(`{LOCALE_ROOT}/*`) do
		if Fs.metadata(path).kind ~= "dir" then
			continue
		end
		local locale = path:match(`^{LOCALE_ROOT}/([^/]+)$`)
		if not locale or not locale:match("^[%a][%w%-]*$") then
			error(`invalid locale directory: {path}`, 0)
		end
		table.insert(found, locale)
	end
	table.sort(found)
	return found
end

local function tagOccurrences(roots: { string }): { { name: string, path: string, line: number, column: number } }
	local occurrences: { { name: string, path: string, line: number, column: number } } = {}
	for _, root in roots do
		for _, path in Glob.Find(`{root}/**`) do
			if not path:match("%.md$") or Fs.metadata(path).kind ~= "file" then
				continue
			end
			local lineNumber = 0
			for line in (Fs.readFile(path) .. "\n"):gmatch("(.-)\n") do
				lineNumber += 1
				local cursor = 1
				while true do
					local first, last, name = line:find("{{tag:([%w_.%-]+)}}", cursor)
					if not first or not last or not name then
						break
					end
					if name ~= "branch_name" then
						table.insert(occurrences, {
							name = name,
							path = path,
							line = lineNumber,
							column = first,
						})
					end
					cursor = last + 1
				end
			end
		end
	end
	return occurrences
end

-- Locate every tag opener that is not part of a complete supported tag.
function TagRenderer.FindMalformed(roots: { string }): { MalformedTag }
	local malformed: { MalformedTag } = {}
	for _, root in roots do
		for _, path in Glob.Find(`{root}/**`) do
			if not path:match("%.md$") or Fs.metadata(path).kind ~= "file" then
				continue
			end
			local lineNumber = 0
			for line in (Fs.readFile(path) .. "\n"):gmatch("(.-)\n") do
				lineNumber += 1
				local cursor = 1
				while true do
					local first = line:find("{{tag:", cursor, true)
					if not first then
						break
					end
					local last = line:find("}}", first + 6, true)
					local token = if last then line:sub(first, last + 1) else line:sub(first)
					if not token:match("^{{tag:[%w_.%-]+}}$") then
						table.insert(malformed, {
							path = path,
							line = lineNumber,
							column = first,
							endColumn = first + math.max(#token, 1),
							token = token,
						})
					end
					cursor = first + math.max(#token, 1)
				end
			end
		end
	end
	return malformed
end

local function missingTagLocation(path: string, tag: string): (number, number, number)
	if Fs.isFile(path) then
		local lineNumber = 0
		for line in (Fs.readFile(path) .. "\n"):gmatch("(.-)\n") do
			lineNumber += 1
			local commentColumn = line:find("#", 1, true)
			local commentedTag: string? = nil
			if commentColumn then
				commentedTag = line:sub(commentColumn + 1):match("^%s*([%w_.%-]+)%s*=")
			end
			if commentedTag == tag then
				return lineNumber, commentColumn or 1, #line + 1
			end
		end
		return lineNumber + 1, 1, 2
	end
	return 1, 1, 2
end

--[[
Check template tags against every locale and locate missing translations at use sites.
]]
function TagRenderer.FindMissing(roots: { string }): { MissingTranslation }
	local locales = localeNames()
	if not table.find(locales, "en") then
		error(`missing English locale directory: {LOCALE_ROOT}/en`, 0)
	end
	local missing: { MissingTranslation } = {}
	local reported: { [string]: boolean } = {}
	for _, occurrence in tagOccurrences(roots) do
		for _, locale in locales do
			local pageTags = readPageTags(locale, occurrence.path)
			if pageTags[occurrence.name] == nil then
				local key = `{locale}:{occurrence.name}`
				if not reported[key] then
					local relative = occurrence.path:gsub("^content/", ""):gsub("%.md$", ".toml")
					local localeFile = `{LOCALE_ROOT}/{locale}/{relative}`
					local line, column, endColumn = missingTagLocation(localeFile, occurrence.name)
					table.insert(missing, {
						path = localeFile,
						line = line,
						column = column,
						endColumn = endColumn,
						locale = locale,
						tag = occurrence.name,
						templatePath = occurrence.path,
						templateLine = occurrence.line,
					})
					reported[key] = true
				end
			end
		end
	end
	return missing
end

function TagRenderer.Validate(roots: { string }): ()
	local missing = TagRenderer.FindMissing(roots)
	if #missing > 0 then
		local messages: { string } = {}
		for _, entry in missing do
			table.insert(
				messages,
				`{entry.path}:{entry.line}: locale {entry.locale} is missing tag {entry.tag}; referenced by {entry.templatePath}:{entry.templateLine}`
			)
		end
		error(`Missing content translations:\n{table.concat(messages, "\n")}`, 0)
	end
end

function TagRenderer.new(locale: string): TagRenderer
	if not locale:match("^[%a][%w%-]*$") then
		error(`invalid content locale: {locale}`, 0)
	end
	local fields: Fields = { locale = locale }
	return setmetatable(fields, TagRenderer)
end

function TagRenderer.Locales(_self: any): { string }
	return localeNames()
end

function TagRenderer.PageData(_self: TagRenderer, source: string): { [string]: any }
	local locales: { [string]: any } = {}
	for _, locale in localeNames() do
		local pageTags = readPageTags(locale, source)
		local indexTags = readPageTags(locale, "content/docs/index.md")
		local localeName = indexTags.locale_name
		if not localeName then
			error(`{LOCALE_ROOT}/{locale}/docs/index.toml: missing tags.locale_name`, 0)
		end
		locales[locale] = { name = localeName, tags = pageTags }
	end
	return { defaultLocale = "en", locales = locales }
end

function TagRenderer.Render(
	self: TagRenderer,
	content: string,
	source: string,
	overrides: { [string]: string }?,
	interactive: boolean?
): string
	-- Normalize line endings so YAML front matter is recognized on Windows and Linux.
	content = content:gsub("\r\n", "\n")
	local tags = readPageTags(self.locale, source)
	local function replaceTags(input: string, makeInteractive: boolean?): string
		local replaced = input:gsub("{{tag:([%w_.%-]+)}}", function(name: string): string
			local value = if overrides then overrides[name] else nil
			value = value or tags[name]
			if not value then
				error(`{source}: locale {self.locale} has no value for tag {name}`, 0)
			end
			if makeInteractive then
				local escaped = value:gsub("&", "&amp;")
				escaped = escaped:gsub("<", "&lt;")
				escaped = escaped:gsub(">", "&gt;")
				escaped = escaped:gsub('"', "&quot;")
				return `<span data-i18n="{name}">{escaped}</span>`
			end
			return value
		end)
		return replaced
	end
	local rendered: string
	if interactive and content:sub(1, 4) == "---\n" then
		local metadataEnd = content:find("\n---\n", 5, true)
		if metadataEnd then
			local endPosition = metadataEnd + 5
			local metadata = replaceTags(content:sub(1, endPosition), false)
			local body = replaceTags(content:sub(endPosition + 1), true)
			rendered = metadata .. body
		else
			rendered = replaceTags(content, true)
		end
	else
		rendered = replaceTags(content, interactive)
	end
	local leftover = rendered:find("{{tag:", 1, true)
	if leftover then
		local line = 1
		for _ in rendered:sub(1, leftover):gmatch("\n") do
			line += 1
		end
		local lineStart = rendered:sub(1, leftover):match(".*\n()") or 1
		local endPosition = rendered:find("}}", leftover + 6, true)
		local token = if endPosition
			then rendered:sub(leftover, endPosition + 1)
			else rendered:sub(leftover):match("^[^\r\n]*") or "{{tag:"
		error(`{source}:{line}:{leftover - lineStart + 1}: malformed content tag {token}`, 0)
	end
	return rendered
end

return TagRenderer
