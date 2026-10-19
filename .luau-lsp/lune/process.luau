--!strict

-- Analyzer-only declaration for the Lune process module.
export type Execution = {
    ok: boolean,
    code: number,
    stdout: string,
    stderr: string,
}

export type StandardStream = "default" | "inherit" | "forward" | "none"

export type ExecutionOptions = {
    cwd: string?,
    env: { [string]: string }?,
    shell: boolean | string?,
    stdio: StandardStream | {
        stdin: string | buffer?,
        stdout: StandardStream?,
        stderr: StandardStream?,
    }?,
}

export type Reader = {
    readToEnd: (self: Reader) -> string,
}

export type Writer = {
    write: (self: Writer, data: string | buffer) -> (),
    close: (self: Writer) -> (),
}

export type Child = {
    stdin: Writer,
    stdout: Reader,
    stderr: Reader,
    status: (self: Child) -> { ok: boolean, code: number },
}

local Process = {} :: {
    os: "linux" | "macos" | "windows",
    arch: "x86_64" | "aarch64",
    cwd: string,
    args: { string },
    env: { [string]: string? },
    exec: (program: string, arguments: { string }?, options: ExecutionOptions?) -> Execution,
    create: (program: string, arguments: { string }?, options: { cwd: string?, env: { [string]: string }? }?) -> Child,
    exit: (code: number?) -> never,
}

return Process
