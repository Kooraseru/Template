--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local configModule = require("../lib/config")
local catalogue = require("../lib/catalogue")
local files = require("../lib/files")
local execute = {}

function execute.run(config: configModule.Config, target: configModule.BuildEntry)
    fs.writeDir("build/logs")
    local container: string? = nil
    local environment: { [string]: string } = table.clone(target.environment or {})
    environment.CARGO_TARGET_DIR = "build/cargo"
    environment.CI_BUILD_TARGET = target.name
    environment.CI_TARGET_TRIPLE = target.target or ""

    local function command(argv: { string }): any
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
            return process.exec("docker", dockerArguments)
        end
        return process.exec(executable, arguments, { env = environment, cwd = process.env.CI_SOURCE_DIR })
    end

    local function prepare()
        if target.image == nil or target.image == "" then
            return
        end
        local image = catalogue.image(target.image)
        local loaded =
            process.exec("docker", { "load", "--input", "build/selected-image/image.tar" })
        assert(loaded.ok, "could not load generated build image: " .. loaded.stderr)

        -- Copy only repository inputs. Docker cp works with a remote/shared
        -- daemon too; it does not assume the job's paths exist on that daemon.
        local staging = "build/tmp/container-input/" .. target.name
        files.reset(staging)
        local listing =
            process.exec("git", { "ls-files", "--cached", "--others", "--exclude-standard", "-z" })
        assert(listing.ok, "could not enumerate repository inputs")
        if process.env.CI_SOURCE_DIR then
            files.copy(process.env.CI_SOURCE_DIR, staging, true)
        else
            for path in listing.stdout:gmatch("[^%z]+") do
                configModule.relative(path)
                files.copy(path, staging .. "/" .. path)
            end
        end
        local created = process.exec("docker", {
            "create",
            "--platform",
            image.platform,
            "--workdir",
            "/workspace",
            "template-ci/" .. image.name .. ":generated",
            "sh",
            "-c",
            "while :; do sleep 3600; done",
        })
        assert(created.ok, "could not create build container: " .. created.stderr)
        local identifier = created.stdout:gsub("%s+$", "")
        container = identifier
        local copied =
            process.exec("docker", { "cp", staging .. "/.", identifier .. ":/workspace" })
        assert(copied.ok, "could not copy repository inputs: " .. copied.stderr)
        local started = process.exec("docker", { "start", identifier })
        assert(started.ok, "could not start build container")
        assert(
            command({ "mkdir", "-p", "build" }).ok,
            "could not create container output directory"
        )
    end

    local function run()
        prepare()
        local probes: { configModule.Probe } = target.probes or {}
        for index, probe in probes do
            local result = command(probe.argv)
            fs.writeFile(
                "build/logs/probe-" .. tostring(index) .. ".log",
                result.stdout .. result.stderr
            )
            print(result.stdout)
            stdio.ewrite(result.stderr)
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
            fs.writeFile(
                "build/logs/command-" .. tostring(index) .. ".log",
                result.stdout .. result.stderr
            )
            print(result.stdout)
            stdio.ewrite(result.stderr)
            assert(result.ok, "project command failed for " .. target.name)
        end
        if #config.build.commands == 0 then
            fs.writeFile("build/logs/build.log", "No project build commands configured.\n")
        end
        return true
    end

    local ok: boolean, failure: any = pcall(run)
    if container then
        local copied =
            process.exec("docker", { "cp", container .. ":/workspace/build/.", "build/" })
        if ok and not copied.ok then
            ok, failure = false, copied.stderr
        end
        process.exec("docker", { "rm", "--force", container })
    end
    assert(ok, tostring(failure))
    if not container and process.env.CI_SOURCE_DIR then
        for _, path in config.build.package_paths do
            files.copy(process.env.CI_SOURCE_DIR .. "/" .. path, path)
        end
    end
end

return execute
