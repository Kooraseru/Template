-- ci/preflight/analyzer.luau
--!strict

-- Delegate full-language parsing and type refinements to the actual Luau
-- analyzer. This is a frontend, not a home-grown approximation of Luau syntax.
local Analyzer = {}

local Process = require("@lune/process")
local Inventory = require("./inventory")

export type Finding = {
    severity: "error" | "warning",
    message: string,
    path: string?,
    line: number?,
    column: number?,
}
export type Outcome = {
    id: string,
    status: "passed" | "failed" | "unavailable",
    findings: { Finding },
    source_count: number,
}

local function unavailable(message: string, count: number): Outcome
    return {
        id = "luau.analysis",
        status = "unavailable",
        source_count = count,
        findings = { { severity = "error", message = message } },
    }
end

local function parseDiagnostics(output: string, fatal: boolean): { Finding }
    local findings: { Finding } = {}
    for line in output:gmatch("[^\r\n]+") do
        local path, row, column, category, message =
            line:match("^(.+)%((%d+),(%d+)%):%s*([^:]+):%s*(.*)$")
        if path and row and column and category and message then
            local severity: "error" | "warning" =
                if fatal or category == "TypeError" or category == "SyntaxError" then "error" else "warning"
            table.insert(findings, {
                severity = severity,
                path = path:gsub("\\", "/"),
                line = tonumber(row),
                column = tonumber(column),
                message = category .. ": " .. message,
            })
        end
    end
    return findings
end

function Analyzer.Run(): Outcome
    local snapshot = Inventory.Read()
    if snapshot.error then
        return unavailable(snapshot.error, #snapshot.files)
    end

    local program = Process.env.CI_LUAU_ANALYZER or "luau-lsp"
    local available, probe = pcall(function()
        return Process.exec(program, { "--version" })
    end)
    if not available or not probe.ok then
        return unavailable(
            "Luau analyzer unavailable; install luau-lsp or set CI_LUAU_ANALYZER to its executable",
            #snapshot.files
        )
    end

    -- Every saved source is checked in its owning language environment.
    -- The rule examples intentionally use Roblox globals; CI itself uses Lune.
    local realms: { { platform: string, files: { string } } } = {
        { platform = "standard", files = {} },
        { platform = "roblox", files = {} },
    }
    for _, path in snapshot.files do
        local realm = if path:match("^rules/languages/luau/structures/.+/examples/") then realms[2] else realms[1]
        table.insert(realm.files, path)
    end

    local findings: { Finding } = {}
    local failed = false
    for _, realm in realms do
        if #realm.files == 0 then
            continue
        end
        local arguments = {
            "analyze",
            "--platform=" .. realm.platform,
            "--flag:LuauSolverV2=true",
            "--base-luaurc=" .. Process.cwd:gsub("[/\\\\]+$", "") .. "/config/luau/.luaurc",
            "--settings=config/luau/luau-lsp/settings.json",
        }
        for _, path in realm.files do
            table.insert(arguments, path)
        end
        local completed, execution = pcall(function()
            return Process.exec(program, arguments)
        end)
        if not completed then
            return unavailable("Luau analysis could not execute: " .. tostring(execution), #snapshot.files)
        end
        for _, finding in parseDiagnostics(execution.stdout .. "\\n" .. execution.stderr, not execution.ok) do
            table.insert(findings, finding)
        end
        if not execution.ok then
            failed = true
            if #parseDiagnostics(execution.stdout .. "\\n" .. execution.stderr, true) == 0 then
                table.insert(findings, {
                    severity = "error",
                    message = "Luau " .. realm.platform .. " analysis failed: " .. execution.stderr .. execution.stdout,
                })
            end
        end
    end
    return {
        id = "luau.analysis",
        status = if failed then "failed" else "passed",
        findings = findings,
        source_count = #snapshot.files,
    }
end

return Analyzer
