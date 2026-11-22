"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "../../../..");
const ID = /^[a-z][a-z0-9-]*$/;
const EXTENSIONS = { node: /\.(?:[cm]?js|ts)$/, bash: /\.sh$/ };
const record = value => value && typeof value === "object" && !Array.isArray(value);

function readCases(name, kind, definitions, folder) {
    if (!record(definitions)) throw new Error(`${name}: expected a ${kind} object`);
    return Object.entries(definitions).sort(([a], [b]) => a.localeCompare(b)).map(([id, spec]) => {
        if (!ID.test(id) || !record(spec) || !Object.hasOwn(EXTENSIONS, spec.runtime) ||
            typeof spec.entry !== "string" || !EXTENSIONS[spec.runtime].test(spec.entry) ||
            !spec.entry.split("/").every(part => /^[\w.-]+$/.test(part) && part !== "." && part !== "..") ||
            !Number.isInteger(spec.timeoutSeconds) || spec.timeoutSeconds < 1 || spec.timeoutSeconds > 3600 ||
            (spec.args !== undefined && (!Array.isArray(spec.args) ||
                !spec.args.every(arg => typeof arg === "string" && !/[\0\r\n]/.test(arg)))) ||
            (spec.optIn !== undefined && typeof spec.optIn !== "boolean")) {
            throw new Error(`${name}/${id}: invalid ${kind} entry in suite.json`);
        }
        const file = path.join(folder, spec.entry);
        const resolved = fs.realpathSync(file);
        const relative = path.relative(fs.realpathSync(folder), resolved);
        if (path.isAbsolute(relative) || relative.startsWith(".." + path.sep) || !fs.statSync(resolved).isFile()) {
            throw new Error(`${name}/${id}: entry must be a file inside the suite`);
        }
        return { ...spec, id, file: resolved };
    });
}

function discover(root = ROOT) {
    const directory = path.join(root, "tests");
    if (!fs.existsSync(directory)) return [];
    return fs.readdirSync(directory, { withFileTypes: true })
        .filter(entry => !(entry.isFile() && ["README.md", ".gitkeep"].includes(entry.name)))
        .sort((a, b) => a.name.localeCompare(b.name))
        .map(entry => {
            const name = entry.name;
            if (!entry.isDirectory() || !ID.test(name)) throw new Error(`Invalid test suite: tests/${name}`);
            const folder = path.join(directory, name);
            const manifest = path.join(folder, "suite.json");
            if (!fs.existsSync(manifest) || !fs.lstatSync(manifest).isFile()) {
                throw new Error(`tests/${name} requires a regular suite.json`);
            }
            const spec = JSON.parse(fs.readFileSync(manifest, "utf8"));
            if (!record(spec) || spec.version !== 1) throw new Error(`${name}: expected suite.json version 1`);
            const checks = readCases(name, "checks", spec.checks, folder);
            const benchmarks = readCases(name, "benchmarks", spec.benchmarks ?? {}, folder);
            if (!checks.length && !benchmarks.length) throw new Error(`${name}: suite has no entries`);
            return { name, checks, benchmarks };
        });
}

function run({ root = ROOT, suite, benchmark = false, selected } = {}) {
    const suites = discover(root).filter(item => !suite || item.name === suite);
    if (suite && !suites.length) throw new Error("Unknown suite: " + suite);
    const kind = benchmark ? "benchmarks" : "checks";
    const jobs = suites.flatMap(item => item[kind].filter(job =>
        selected ? job.id === selected : !job.optIn).map(job => ({ ...job, suite: item.name })));
    if ((suite || benchmark || selected) && !jobs.length) throw new Error("No matching " + kind);
    for (const job of jobs) {
        const program = job.runtime === "node" ? process.execPath : process.env.TEST_SUITE_BASH || "bash";
        const args = [...(job.runtime === "node" && /\.test\.[^.]+$/.test(job.entry) ? ["--test"] : []),
            job.file, ...(job.args || [])];
        const env = { ...process.env };
        delete env.NODE_TEST_CONTEXT;
        console.log(`${kind}: ${job.suite}/${job.id}`);
        const result = spawnSync(program, args, { cwd: root, env, stdio: "inherit", timeout: job.timeoutSeconds * 1000 });
        if (result.error || result.status !== 0) {
            throw new Error(`${job.suite}/${job.id} failed: ${result.error?.message || result.signal || "exit " + result.status}`);
        }
    }
}

if (require.main === module) {
    try {
        const args = process.argv.slice(2);
        const benchmark = args.includes("--benchmark");
        const positional = args.filter(arg => arg !== "--benchmark");
        if (positional.length > 2 || positional.some(arg => !ID.test(arg))) {
            throw new Error("Usage: run.cjs [suite] [case] [--benchmark]");
        }
        run({ suite: positional[0], selected: positional[1], benchmark });
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}

module.exports = { discover, run };
