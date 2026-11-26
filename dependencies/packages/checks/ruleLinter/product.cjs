"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { loadPolicy } = require("./policy.cjs");
const root = path.resolve(__dirname, "../../../..");

async function run({ workspace = root, family, product, output, mode = "check" }) {
    const policy = loadPolicy(workspace);
    const entries = [...policy.rules.values()].filter(rule => rule.runtime === "node-product" && rule.id.startsWith(family + "/"));
    if (!entries.length) throw new Error("No product rules discovered for " + family);
    const reports = [];
    for (const rule of entries) {
        const config = policy.result.get(rule.id);
        const destination = path.join(output, rule.id.split("/").at(-1));
        fs.mkdirSync(destination, { recursive: true });
        const report = { rule: rule.id, mode, severity: config.severity, status: "failed", findings: [], coverage: [] };
        try {
            if (config.overrides?.length) throw new Error("Product rules cannot use source-file overrides");
            if (mode === "check" && config.severity === "off") report.status = "disabled";
            else {
                const module = require(path.join(workspace, rule.entry));
                const validator = rule.schema ? module.Create(config.settings ?? {}) : module;
                if (typeof validator.Check !== "function") throw new Error("Product validator must export Check");
                const result = await validator.Check({ root: workspace, product, output: destination, mode, rule });
                if (!Array.isArray(result?.findings) || !Array.isArray(result?.coverage) || !result.coverage.length)
                    throw new Error("Product validator returned no coverage or invalid result");
                for (const item of result.findings) {
                    if (!item.file || !Number.isInteger(item.line) || !Number.isInteger(item.column) || typeof item.message !== "string")
                        throw new Error("Invalid product finding");
                    const relative = path.relative(workspace, path.resolve(workspace, item.file));
                    if (!relative || relative.startsWith(".." + path.sep) || relative === ".." || path.isAbsolute(relative)) throw new Error("Finding escaped workspace");
                }
                report.findings = result.findings;
                report.coverage = result.coverage;
                report.status = result.findings.some(item => item.infrastructure) || result.coverage.some(item => item.status === "failed") ? "failed" : result.coverage.some(item => item.status === "unverified") ? "unverified" : result.findings.length ? "different" : mode === "capture" ? "captured" : "passed";
            }
        } catch (error) {
            report.findings.push({ file: rule.readme, line: 1, column: 1, message: String(error.message || error), infrastructure: true });
        }
        for (const item of report.findings) {
            const severity = item.infrastructure ? "error" : config.severity;
            console.log("::rule-finding::" + JSON.stringify({ ...item, rule: rule.id, ruleDoc: rule.readme, severity, checkerFailure: !!item.infrastructure }));
        }
        fs.writeFileSync(path.join(destination, "report.json"), JSON.stringify(report, null, 2) + "\n");
        reports.push(report);
    }
    const failed = reports.some(report => report.status === "failed" || ["different","unverified"].includes(report.status) && report.severity === "error");
    return { reports, failed };
}
if (require.main === module) {
    const [family, product, output, flag] = process.argv.slice(2);
    if (!family || !product || !output || flag && flag !== "--capture") {
        console.error("Usage: product.cjs <family> <built-product> <output> [--capture]");
        process.exitCode = 1;
    } else run({ family, product: path.resolve(product), output: path.resolve(output), mode: flag ? "capture" : "check" })
        .then(({ reports, failed }) => {
            const summary = reports.map(r => r.rule + ": " + r.status + " (" + r.findings.length + " findings; " + r.coverage.length + " scenarios)").join("\n");
            console.log(summary);
            if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, "## Product rules\n\n" + summary + "\n");
            if (failed) process.exitCode = 1;
        }).catch(error => { console.error(error); process.exitCode = 1; });
}
module.exports = { run };
