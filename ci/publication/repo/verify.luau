-- ci/publication/repo/verify.luau
--!strict

local VerifyRepository = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Rules = require("../../validation/rules")

--# Functions

function VerifyRepository.Check(raw: unknown, source: string?, repository: string?)
	assert(source and #source == 40 and source:match("^[a-f0-9]+$"), "missing publication source identity")
	assert(repository and repository:match("^[^/%s]+/[^/%s]+$"), "missing publication repository identity")
	local record = Rules.Entries(raw)
	assert(
		record.source == source and record.repository == repository,
		"Publication artifact does not match this source run"
	)
end

function VerifyRepository.Run()
	VerifyRepository.Check(
		Serde.decode("json", Fs.readFile("build/repo/publication.json")),
		Process.env.GITHUB_SHA,
		Process.env.GITHUB_REPOSITORY
	)
end

return VerifyRepository
