-- ci/integration/github/init.luau
--!strict

-- This boundary validates the chosen capability before touching GitHub APIs.
-- No operation receives extra permissions by running inside a workflow.
local GitHubIntegration = {}

local Process = require("@lune/process")
local Labels = require("@self/labels")
local Projects = require("@self/projects")

function GitHubIntegration.Run(arguments: { string })
    local resource, action = arguments[1], arguments[2]
    assert(#arguments == 2, "github expects a resource and operation")
    assert(resource == "labels" or resource == "projects", "unsupported GitHub resource")
    assert(action == "validate" or action == "plan" or action == "apply", "unsupported GitHub operation")

    if action == "apply" then
        assert(Process.env.GITHUB_ACTIONS ~= "true", "GitHub project/label mutation requires an authenticated local user")
    end
    if resource == "labels" then
        Labels.Run(action)
    else
        Projects.Run(action)
    end
end

return GitHubIntegration
