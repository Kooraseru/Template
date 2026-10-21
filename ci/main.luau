--!strict
-- Single public Luau dispatcher: explicitly enumerated operations only.
local Process = require("@lune/process")
local Stdio = require("@lune/stdio")
local AgentRules = require("./libraries/registry/agent-rules")

local args = Process.args
local op = args[1]

if op == "rules" then
    assert(args[3] == nil, "unexpected rules arguments")
    if args[2] == "sync" then
        AgentRules.Sync()
    elseif args[2] == "check" then
        AgentRules.Check()
    else
        error("rules expects sync or check")
    end
elseif op == "native-compat" then
    assert(args[2] == nil, "unexpected native-compat arguments")
    local result = Process.exec("node", { "--test", "ci/libraries/bootstrap/native.test.mjs" })
    print(result.stdout)
    assert(result.ok, result.stderr)
elseif op == "repo-publish" then
    assert(args[2] == nil, "unexpected repo-publish arguments")
    require("./security/access/require-publication").Run()
    local result = Process.exec("bash", { "ci/publication/repo/publish-internal.sh" })
    assert(result.ok, result.stderr)
    print(result.stdout)
elseif op == "release-publish" then
    assert(args[2] == nil, "unexpected release-publish arguments")
    require("./security/access/require-publication").Run()
    require("./publication/releases/publish").Run()
else
    local subject
    if op == "validate" then subject = require("./validation/run")
    elseif op == "template-check" then subject = require("./validation/template")
    elseif op == "integration-refresh-prs" then subject = require("./integration/refresh-prs")
    elseif op == "local-actions" then subject = require("./integration/local-actions")
    elseif op == "configure-editor" then subject = require("./integration/configure-editor")
    elseif op == "integration-dispatch" then subject = require("./integration/dispatch")
    elseif op == "integration-gate" then subject = require("./integration/gate")
    elseif op == "access-resolve" then subject = require("./security/access/resolve")
    elseif op == "access-require-publication" then subject = require("./security/access/require-publication")
    elseif op == "receipts" then subject = require("./security/receipts/cli")
    elseif op == "validation-gate" then subject = require("./validation/gate")
    elseif op == "images-build" then subject = require("./fabricator/distribution/images/build")
    elseif op == "targets-build" then subject = require("./fabricator/workflow")
    elseif op == "distribution-package" then subject = require("./fabricator/distribution/package")
    elseif op == "release-cli" then subject = require("./publication/releases/cli")
    elseif op == "release-build" then subject = require("./publication/releases/build")
    elseif op == "repo-build" then subject = require("./publication/repo/build")
    elseif op == "repo-verify" then subject = require("./publication/repo/verify")
    elseif op == "pages-build" then subject = require("./publication/pages/build")
    else error("unknown CI operation: " .. tostring(op), 0)
    end
    -- The Lune-provided Process.args table is read-only. Forward an explicit slice.
    local forwarded: { string } = {}
    for index = 2, #args do table.insert(forwarded, args[index]) end
    local function stage(name: string, opening: boolean)
        Stdio.write(if opening then "::group::Validate / " .. name .. "\n" else "::endgroup::\n")
    end
    if subject.Cases then
        subject:Run()
    else
        if op == "validate" then subject.Run(stage) else subject.Run(forwarded) end
    end
end
