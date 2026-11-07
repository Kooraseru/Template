import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test, { type TestContext } from "node:test";
import { gzipSync } from "node:zlib";
import { extract } from "./archive.ts";

function temporary(context: TestContext): string {
	const directory = fs.mkdtempSync(path.join(os.tmpdir(), "dependency-test-"));
	context.after(() => {
		if (!directory.startsWith(path.join(os.tmpdir(), "dependency-test-")))
			throw new Error("Unsafe cleanup path");
		fs.rmSync(directory, { recursive: true, force: true });
	});
	return directory;
}

function archive(
	entries: { name: string; type: string; body?: string; link?: string }[],
): Buffer {
	const parts: Buffer[] = [];
	for (const entry of entries) {
		const body = Buffer.from(entry.body || "");
		const header = Buffer.alloc(512);
		header.write(entry.name, 0, 100);
		header.write("0000755\0", 100, 8);
		header.write(body.length.toString(8).padStart(11, "0") + "\0", 124, 12);
		header.write(entry.type, 156, 1);
		if (entry.link) header.write(entry.link, 157, 100);
		parts.push(header, body, Buffer.alloc((512 - (body.length % 512)) % 512));
	}
	parts.push(Buffer.alloc(1024));
	return gzipSync(Buffer.concat(parts));
}

test("materializes internal TAR file aliases without creating symlinks", (context) => {
	const directory = temporary(context);
	extract(
		directory,
		"release.tar.gz",
		archive([
			{ name: "release/bin/tool-server", type: "2", link: "tool" },
			{ name: "release/bin/tool", type: "0", body: "executable" },
		]),
		"tool",
	);
	assert.equal(
		fs.readFileSync(path.join(directory, "release/bin/tool-server"), "utf8"),
		"executable",
	);
	assert.equal(
		fs
			.lstatSync(path.join(directory, "release/bin/tool-server"))
			.isSymbolicLink(),
		false,
	);
});

test("rejects TAR links that escape the extraction directory", (context) => {
	assert.throws(
		() =>
			extract(
				temporary(context),
				"release.tgz",
				archive([{ name: "release/tool", type: "2", link: "../../outside" }]),
				"tool",
			),
		/Unsafe archive path/,
	);
});

test("rejects unresolved TAR link cycles", (context) => {
	assert.throws(
		() =>
			extract(
				temporary(context),
				"release.tgz",
				archive([
					{ name: "one", type: "2", link: "two" },
					{ name: "two", type: "2", link: "one" },
				]),
				"one",
			),
		/Unresolved archive link/,
	);
});
