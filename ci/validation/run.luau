-- ci/validation/run.luau
--!strict

-- Execute real repository checks and record their outcomes. There is no
-- synthetic test registry; publication verifies receipts against real artifacts.
local Validation = {}

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Datetime = require("@lune/datetime")
local Request = require("../integration/request")
local Policy = require("./policy")
local Repository = require("./repository")
local Workflows = require("./workflows")
local Releases = require("../publication/releases/validate")

type Check = { path: string, success: boolean, error: string? }
type Group = { name: string, checks: { Check } }

local function append(path: string, value: string)
    Fs.writeFile(path, (if Fs.isFile(path) then Fs.readFile(path) else "") .. value)
end

function Validation.Run(onStage: ((string, boolean) -> ())?)
    local controls = Request.Read()
    local revision = Process.exec("git", { "rev-parse", "HEAD" })
    assert(revision.ok, "cannot identify controller revision")
    local evidence = {
        controller_sha = revision.stdout:gsub("%s+$", ""),
        tested_sha = Process.env.CI_TESTED_SHA,
        controls = controls,
        created_at = Datetime.now():toIsoDate(),
        groups = {} :: { Group },
        success = true,
    }
    local summary = { "\n## Validation results", "", "| Stage | Result |", "| --- | --- |" }

    local function stage(name: string, checks: { { path: string, Run: () -> () } })
        if controls.validation_scope ~= "All" and controls.validation_scope ~= name then
            return
        end
        if onStage then onStage(name, true) end
        local group: Group = { name = name, checks = {} }
        for _, check in checks do
            local ok, failure = pcall(check.Run)
            table.insert(group.checks, {
                path = check.path,
                success = ok,
                error = if ok then nil else tostring(failure),
            })
            evidence.success = evidence.success and ok
        end
        table.insert(evidence.groups, group)
        if onStage then onStage(name, false) end
        table.insert(summary, "| " .. name .. " | " .. (if evidence.success then "Passed" else "Failed") .. " |")
    end

    stage("Configuration", {
        { path = "ci/validation/policy.luau", Run = Policy.Run },
        { path = "ci/validation/repository.luau", Run = Repository.Run },
    })
    stage("Workflow rules", {
        { path = "ci/validation/workflows.luau", Run = Workflows.Run },
    })
    stage("Release tooling", {
        { path = "ci/publication/releases/validate.luau", Run = Releases.Run },
    })

    -- Neither access authorization nor receipt verification has a meaningful
    -- fixture-free result absent the actual event and signed artifacts.
    if controls.validation_scope ~= "All" and #evidence.groups == 0 then
        error("selected validation scope requires live authorization/artifact evidence")
    end

    Fs.writeDir("build/validation")
    Fs.writeFile("build/validation/evidence.json", Serde.encode("json", evidence, true))
    if Process.env.GITHUB_STEP_SUMMARY then
        append(Process.env.GITHUB_STEP_SUMMARY, table.concat(summary, "\n") .. "\n")
    end
    assert(evidence.success, "repository validation failed; inspect stage checks")
end

return Validation
