-- ci/build/execute.luau
--!strict
local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Stdio = require("@lune/stdio")
local Serde = require("@lune/serde")
local ConfigModule = require("../lib/config")
local Catalogue = require("../lib/catalogue")
local Files = require("../lib/files")

return function(config: ConfigModule.Config, target: ConfigModule.BuildEntry)
    Fs.writeDir("build/logs")
    local container: string? = nil
    local environment: { [string]: string } = table.clone(target.environment or {})
    environment.CARGO_TARGET_DIR = "build/cargo"
    environment.CI_BUILD_TARGET = target.name
    environment.CI_TARGET_TRIPLE = target.target or ""

    local function command(argv: { string }): Process.Execution
        local arguments = table.clone(argv)
        local executable = assert(table.remove(arguments, 1), "missing command executable")
        if container then
            local dockerArguments = { "exec", "--workdir", "/workspace" }
            for key, value in environment do
                table.insert(dockerArguments, "--env")
                table.insert(dockerArguments, key .. "=" .. value)
            end
            table.insert(dockerArguments, container)
            table.insert(dockerArguments, executable)
            for _, argument in arguments do
                table.insert(dockerArguments, argument)
            end
            return Process.exec("docker", dockerArguments)
        end
        -- Windows resolves a relative program path before applying cwd.
        -- Resolve checkout-local programs explicitly; leave PATH commands alone.
        local sourceDirectory = Process.env.CI_SOURCE_DIR
        if sourceDirectory and executable:find("[/\\]")
            and not executable:match("^[/\\]") and not executable:match("^%a:") then
            executable = sourceDirectory .. "/" .. executable
        end
        return Process.exec(executable, arguments, { env = environment, cwd = Process.env.CI_SOURCE_DIR })
    end

    local function prepare()
        if target.image == nil or target.image == "" then
            return
        end
        local image = Catalogue.Image(target.image)
        local imageRecord = Serde.decode("json", Fs.readFile("build/selected-image/image.json")) :: {
            name: string, platform: string, base: string, tag: string?, id: string,
        }
        assert(imageRecord.name == image.name and imageRecord.platform == image.platform
            and imageRecord.base == image.base, "selected image definition mismatch")
        local tag = imageRecord.tag or ("template-ci/" .. image.name .. ":generated")
        if Process.env.CI_BUILD_SPEC then
            local spec = Serde.decode("json", Process.env.CI_BUILD_SPEC) :: ConfigModule.BuildSpec
            assert(tag == "template-ci/" .. image.name .. ":" .. spec.image_artifact, "selected image identity mismatch")
        end
        local loaded =
            Process.exec("docker", { "load", "--input", "build/selected-image/image.tar" })
        assert(loaded.ok, "could not load generated build image: " .. loaded.stderr)
        local inspected = Process.exec("docker", { "image", "inspect", tag, "--format", "{{json .}}" })
        assert(inspected.ok, "could not inspect loaded build image")
        local imageIdentity = Serde.decode("json", inspected.stdout) :: { Id: string, Os: string, Architecture: string }
        assert(imageIdentity.Id == imageRecord.id and imageIdentity.Os .. "/" .. imageIdentity.Architecture == image.platform,
            "loaded image identity or platform mismatch")

        -- Copy a standalone source checkout, including its selected Git HEAD.
        -- Docker cp works with remote/shared daemons without host-path mounts.
        local staging = "build/tmp/container-input/" .. target.name
        Files.Reset(staging)
        local listing =
            Process.exec("git", { "ls-files", "--cached", "--others", "--exclude-standard", "-z" })
        assert(listing.ok, "could not enumerate repository inputs")
        if Process.env.CI_SOURCE_DIR then
            Files.Copy(Process.env.CI_SOURCE_DIR, staging)
        else
            for path in listing.stdout:gmatch("[^%z]+") do
                ConfigModule.Relative(path)
                Files.Copy(path, staging .. "/" .. path)
            end
        end
        local created = Process.exec("docker", {
            "create",
            "--platform",
            image.platform,
            "--workdir",
            "/workspace",
            imageRecord.id,
            "sh",
            "-c",
            "while :; do sleep 3600; done",
        })
        assert(created.ok, "could not create build container: " .. created.stderr)
        local identifier = created.stdout:gsub("%s+$", "")
        container = identifier
        local copied =
            Process.exec("docker", { "cp", staging .. "/.", identifier .. ":/workspace" })
        assert(copied.ok, "could not copy repository inputs: " .. copied.stderr)
        local started = Process.exec("docker", { "start", identifier })
        assert(started.ok, "could not start build container")
        assert(
            command({ "mkdir", "-p", "build" }).ok,
            "could not create container output directory"
        )
    end

    local function run()
        prepare()
        local probes: { ConfigModule.Probe } = target.probes or {}
        for index, probe in probes do
            local result = command(probe.argv)
            Fs.writeFile(
                "build/logs/probe-" .. tostring(index) .. ".log",
                result.stdout .. result.stderr
            )
            print(result.stdout)
            Stdio.ewrite(result.stderr)
            assert(result.code == probe.code, "toolchain probe failed for " .. target.name)
            if probe.stdout_contains then
                assert(
                    result.stdout:find(probe.stdout_contains, 1, true),
                    "unexpected toolchain output"
                )
            end
        end
        for index, argv in config.build.commands do
            local result = command(argv)
            Fs.writeFile(
                "build/logs/command-" .. tostring(index) .. ".log",
                result.stdout .. result.stderr
            )
            print(result.stdout)
            Stdio.ewrite(result.stderr)
            assert(result.ok, "project command failed for " .. target.name)
        end
        if #config.build.commands == 0 then
            Fs.writeFile("build/logs/build.log", "No project build commands configured.\n")
        end
        return true
    end

    local ok, failure = pcall(run)
    if container then
        local copied =
            Process.exec("docker", { "cp", container .. ":/workspace/build/.", "build/" })
        if ok and not copied.ok then
            ok, failure = false, copied.stderr
        end
        Process.exec("docker", { "rm", "--force", container })
    end
    assert(ok, tostring(failure))
    if not container and Process.env.CI_SOURCE_DIR then
        for _, path in config.build.package_paths do
            Files.Copy(Process.env.CI_SOURCE_DIR .. "/" .. path, path)
        end
    end
end
