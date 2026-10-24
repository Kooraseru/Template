-- ci/validation/repository.luau
--!strict

-- Validate source-owned build declarations against actual manifests.
local Repository = {}

local Fs = require("@lune/fs")
local Configuration = require("../fabricator/config")
local Targets = require("../fabricator/targets")

function Repository.Run()
    local config = Configuration.Read()
    Targets.Discover(config.targets)
    for _, path in config.build.package_paths do
        assert(Fs.isFile(path) or Fs.isDir(path), "missing package input: " .. path)
    end
end

return Repository
