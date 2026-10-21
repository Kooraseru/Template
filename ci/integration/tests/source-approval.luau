-- ci/integration/tests/source-approval.luau
--!strict

local SourceApprovalTests = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../../libraries/registry/rules")
local Files = require("../../libraries/bootstrap/files")
local SourceApproval = require("../source-approval")
local Base64 = require("../../libraries/bootstrap/base64")

--# Functions

function SourceApprovalTests.Run()
	local document = Rules.Entries(Serde.decode("json", Fs.readFile("ci/integration/ruleset.json")))
	local definition = Rules.Entries(document.sourceApproval)
	local baseline = Rules.Entries(definition.baseline)
	local root = "build/tests/source-approval"
	Files.Reset(root)
	local success, failure = pcall(function()
		for _, raw in Rules.Array(definition.cases) do
			local case = Rules.Entries(raw)
			local env: { [string]: string? } = {}

			for key, value in baseline do
				assert(type(key) == "string" and type(value) == "string", "invalid source approval environment")
				env[key] = value
			end

			for key, value in Rules.Entries(case.patch or {}) do
				assert(type(key) == "string" and type(value) == "string", "invalid environment patch")
				env[key] = value
			end

			local sha = env.GITHUB_SHA
			local pr = {
				number = 17,
				merged = true,
				merged_at = "2026-10-16T00:00:00Z",
				merge_commit_sha = sha,
				base = { ref = "source", repo = { full_name = env.GITHUB_REPOSITORY } },
				merged_by = { login = "admin" },
			}

			if type(case.event) == "table" then
				env.GITHUB_EVENT_PATH = root .. "/event.json"
				Fs.writeFile(assert(env.GITHUB_EVENT_PATH), Serde.encode("json", case.event))
			end

			local approval = SourceApproval.Read(env, {
				IsAdmin = function(login: string?): boolean
					return login == "admin"
				end,
				Api = function(route: string): unknown
					if route:find("/commits/", 1, true) then
						return if case.direct then {} else { pr }
					end

					assert(route:match("/pulls/17$"), "unexpected source approval request")
					return pr
				end,
			})
			assert(
				(if approval then approval.kind else "none") == case.expected,
				"source approval case: " .. tostring(case.name)
			)
		end

		for _, raw in Rules.Array(definition.base64) do
			local case = Rules.Entries(raw)
			assert(type(case.text) == "string" and type(case.encoded) == "string", "invalid base64 case")
			assert(
				Base64.Encode(case.text) == case.encoded and Base64.Decode(case.encoded) == case.text,
				"base64 round trip failed"
			)
		end

		for _, invalid in Rules.Array(definition.invalidBase64) do
			assert(type(invalid) == "string" and not pcall(Base64.Decode, invalid), "malformed base64 accepted")
		end
	end)
	Files.Reset(root)
	assert(success, tostring(failure))
end

return SourceApprovalTests
