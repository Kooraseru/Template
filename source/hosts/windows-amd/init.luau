-- source/hosts/windows-amd/init.luau
--!strict

-- The AMD host controls its own toolchain and output.
local Process = require("@lune/process")

return function()
    local image = "template-windows-amd"
    local built = Process.exec("docker", { "build", "--file", "source/hosts/windows-amd/Dockerfile", "--tag", image, "." })
    if not built.ok then error(built.stderr, 0) end
    local result = Process.exec("docker", {
        "run", "--rm", "--volume", `{Process.cwd}:/workspace`, image,
        "x86_64-w64-mingw32-clang", "-O2", "-DHOST_MESSAGE=\"Windows 11 x86-64 AMD\"",
        "source/main.c", "-o", "build/windows-amd.exe",
    })
    if not result.ok then error(result.stderr, 0) end
end
