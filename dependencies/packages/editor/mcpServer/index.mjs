import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import problems from "./problems.cjs";
import rules from "./rules.cjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../..");

function toolResult(value) {
	return {
		content: [{ type: "text", text: JSON.stringify(value) }],
		structuredContent: value,
	};
}

function toolError(error) {
	return {
		isError: true,
		content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }],
	};
}

async function main() {
	// The workspace dependency loader owns the SDK installation and lockfile.
	const requireWorkspace = createRequire(path.join(root, "dependencies/managed/npm/package.json"));
	let McpServer, fromJsonSchema, serveStdio;
	try {
		({ McpServer, fromJsonSchema } = await import(pathToFileURL(requireWorkspace.resolve("@modelcontextprotocol/server")).href));
		({ serveStdio } = await import(pathToFileURL(requireWorkspace.resolve("@modelcontextprotocol/server/stdio")).href));
	} catch (error) {
		throw new Error("MCP SDK unavailable. Run the workspace dependency loader before starting the server.", { cause: error });
	}

	serveStdio(() => {
		const server = new McpServer({ name: "template-workspace", version: "0.1.0" }, {
			instructions: "Use editor_get_problems for live VS Code diagnostics; the result is scoped to this workspace and can lag an edit. If the editor is unavailable, use the workspace CLI, never assume zero errors. Use rules_list to locate Luau rule validators and test fixtures before searching directories. A rule inventory is not an audit. Both tools are read-only. Do not use this server to execute source or mutate workspace state.",
		});

		server.registerTool("editor_get_problems", {
			description: "Read the live VS Code Problems for this workspace via Workbench Bridge. Use for editor diagnostics, including unsaved editor state; if unavailable, use a workspace CLI rather than assuming there are no errors. Results are scoped and capped.",
			annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
			inputSchema: fromJsonSchema({
				type: "object",
				additionalProperties: false,
				properties: {
					file: { type: "string", minLength: 1, description: "Optional workspace-relative file path to inspect." },
					severity: { type: "string", enum: ["error", "warning", "information", "hint"], description: "Optional diagnostic severity filter." },
					limit: { type: "integer", minimum: 1, maximum: 100, default: 25, description: "Maximum diagnostics returned; totals still cover the selected scope." },
				},
			}),
		}, async args => {
			try { return toolResult(await problems.getProblems({ root, ...args })); }
			catch (error) { return toolError(error); }
		});

		server.registerTool("rules_list", {
			description: "Discover the actual Luau rule directories and fixture counts in this workspace. This is an inventory, not an audit, lint result, or proof of correctness. Use before reviewing a rule or selecting validation fixtures.",
			annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
			inputSchema: fromJsonSchema({
				type: "object",
				additionalProperties: false,
				properties: {
					id: { type: "string", minLength: 1, description: "Optional full rule ID or unambiguous rule name." },
				},
			}),
		}, async args => {
			try { return toolResult(rules.listRules({ root, ...args })); }
			catch (error) { return toolError(error); }
		});

		return server;
	});
}

main().catch(error => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});
