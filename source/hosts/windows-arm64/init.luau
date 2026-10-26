-- source/hosts/windows-arm64/init.luau
--!strict

-- Host-specific build entry. This implementation owns its compiler and image.
local Process = require("@lune/process")

local image = "template-windows-arm64"
local dockerfile = "source/hosts/windows-arm64/Dockerfile"

return function()
    local built = Process.exec("docker", { "build", "--file", dockerfile, "--tag", image, "." })
    if not built.ok then
        error(built.stderr, 0)
    end
    local result = Process.exec("docker", {
        "run", "--rm", "--volume", `{Process.cwd}:/workspace`, image,
        "aarch64-w64-mingw32-clang", "-O2", "-DHOST_MESSAGE=\"Windows 11 ARM64\"",
        "source/main.c", "-o", "build/windows-arm64.exe",
    })
    if not result.ok then
        error(result.stderr, 0)
    end
end
