-- repo/ci/github/nativeJob.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Publication = require("./publication")

local NativeJob = {}

export type Step = {
	name: string?,
	id: string?,
	["continue-on-error"]: boolean?,
	uses: string?,
	run: string?,
	["if"]: string?,
	with: { [string]: unknown }?,
	env: { [string]: string }?,
}

local function optionalText(value: unknown): string?
	if value == nil then
		return nil
	end
	return Publication.Text(value)
end

local function strings(value: unknown): { [string]: string }
	local result: { [string]: string } = {}
	for key, item in Publication.Record(value) do
		result[key] = Publication.Text(item)
	end
	return result
end

-- Component-owned native adapters are data, never another component inventory.
function NativeJob.Configure(identity: string, boundary: string, steps: { Step }, job: { [string]: unknown }): ()
	local path = `repo/ci/components/{identity}/github.toml`
	if not Fs.isFile(path) then
		return
	end
	local configuration = Publication.Record(Serde.decode("toml", Fs.readFile(path)))
	for field in configuration do
		if field ~= "permissions" and field ~= "environment" and field ~= "steps" then
			error(`{path}: unsupported native job field {field}`, 0)
		end
	end
	if configuration.permissions then
		local permissions = strings(configuration.permissions)
		for _, permission in permissions do
			if permission ~= "read" and permission ~= "write" and permission ~= "none" then
				error(`{path}: invalid native permission value`, 0)
			end
			if permission == "write" and boundary ~= "privileged" then
				error(`{path}: native write permissions require a privileged component`, 0)
			end
		end
		job.permissions = permissions
	end
	if configuration.environment then
		job.environment = strings(configuration.environment)
	end
	local nativeSteps = configuration.steps
	if type(nativeSteps) ~= "table" then
		error(`{path}: expected native steps array`, 0)
	end
	for _, value in nativeSteps do
		local record = Publication.Record(value)
		for field in record do
			if
				field ~= "name"
				and field ~= "id"
				and field ~= "uses"
				and field ~= "run"
				and field ~= "if"
				and field ~= "with"
				and field ~= "env"
				and field ~= "continue-on-error"
			then
				error(`{path}: unsupported native step field {field}`, 0)
			end
		end
		local continueOnError = record["continue-on-error"]
		if continueOnError ~= nil and type(continueOnError) ~= "boolean" then
			error(`{path}: continue-on-error must be boolean`, 0)
		end
		local step: Step = {
			["continue-on-error"] = continueOnError,
			name = optionalText(record.name),
			id = optionalText(record.id),
			uses = optionalText(record.uses),
			run = optionalText(record.run),
			["if"] = optionalText(record["if"]),
			with = if record.with then Publication.Record(record.with) else nil,
			env = if record.env then strings(record.env) else nil,
		}
		if (step.uses == nil) == (step.run == nil) then
			error(`{path}: native step requires exactly one of uses or run`, 0)
		end
		table.insert(steps, step)
	end
end

return NativeJob
