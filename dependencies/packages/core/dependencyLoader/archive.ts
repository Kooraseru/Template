import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import fflate from "./vendor/fflate.cjs";

const unzipContents = fflate.unzipSync as (
	bytes: Buffer,
) => Record<string, Buffer>;

const MAX_SIZE = 512 * 1024 * 1024;
const MAX_FILES = 20000;

function destination(root: string, name: string) {
	if (
		!name ||
		name.includes("\\") ||
		name.startsWith("/") ||
		name.includes("\0") ||
		/^[A-Za-z]:/.test(name)
	)
		throw new Error(`Unsafe archive path: ${name}`);
	const parts = name.split("/").filter(Boolean);
	if (
		parts.some(
			(part: string) => part === ".." || part === "." || part.includes(":"),
		)
	)
		throw new Error(`Unsafe archive path: ${name}`);
	const target = path.resolve(root, ...parts);
	if (!target.startsWith(path.resolve(root) + path.sep))
		throw new Error(`Unsafe archive path: ${name}`);
	return target;
}

function write(root: string, name: string, data: Uint8Array) {
	const target = destination(root, name);
	fs.mkdirSync(path.dirname(target), { recursive: true });
	fs.writeFileSync(target, data, { flag: "wx" });
}

function unzip(root: string, bytes: Buffer) {
	let eocd = -1;
	for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
		if (
			bytes.readUInt32LE(i) === 0x06054b50 &&
			i + 22 + bytes.readUInt16LE(i + 20) === bytes.length
		) {
			eocd = i;
			break;
		}
	}
	if (eocd < 0) throw new Error("Invalid ZIP archive");
	const count = bytes.readUInt16LE(eocd + 10);
	let offset = bytes.readUInt32LE(eocd + 16);
	if (count > MAX_FILES || count === 65535 || offset === 0xffffffff)
		throw new Error("Unsupported ZIP size");
	let total = 0;
	for (let i = 0; i < count; i++) {
		if (offset + 46 > bytes.length || bytes.readUInt32LE(offset) !== 0x02014b50)
			throw new Error("Invalid ZIP directory");
		const size = bytes.readUInt32LE(offset + 24);
		const nameLength = bytes.readUInt16LE(offset + 28);
		const extraLength = bytes.readUInt16LE(offset + 30);
		const commentLength = bytes.readUInt16LE(offset + 32);
		const end = offset + 46 + nameLength + extraLength + commentLength;
		if (end > bytes.length || size === 0xffffffff)
			throw new Error("Unsupported ZIP entry");
		const name = bytes.toString("utf8", offset + 46, offset + 46 + nameLength);
		destination(root, name);
		total += size;
		if (total > MAX_SIZE) throw new Error("Archive exceeds size limit");
		offset = end;
	}
	const contents = unzipContents(bytes);
	for (const [name, data] of Object.entries(contents)) {
		if (!name.endsWith("/")) write(root, name, data);
	}
}

function untar(root: string, compressed: Buffer) {
	const bytes = zlib.gunzipSync(compressed, { maxOutputLength: MAX_SIZE });
	let count = 0;
	let paxPath;
	const links: { name: string; target: string }[] = [];
	for (let offset = 0; offset + 512 <= bytes.length;) {
		const header = bytes.subarray(offset, offset + 512);
		if (header.every((byte: number) => byte === 0)) break;
		const text = (start: number, length: number) =>
			header
				.subarray(start, start + length)
				.toString("utf8")
				.replace(/\0.*$/, "");
		const rawSize = text(124, 12).trim();
		if (!/^[0-7]*$/.test(rawSize)) throw new Error("Unsupported TAR size");
		const size = parseInt(rawSize || "0", 8);
		const dataStart = offset + 512;
		if (dataStart + size > bytes.length || ++count > MAX_FILES)
			throw new Error("Invalid TAR archive");
		const type = String.fromCharCode(header[156] || 48);
		let name = (text(345, 155) ? text(345, 155) + "/" : "") + text(0, 100);
		if (type === "x") {
			const records = bytes
				.subarray(dataStart, dataStart + size)
				.toString("utf8");
			for (const line of records.split("\n")) {
				const match = line.match(/^\d+ path=(.*)$/);
				if (match) paxPath = match[1];
			}
		} else if (type === "g") {
			// Global metadata does not create a file.
		} else {
			if (paxPath) name = paxPath;
			paxPath = undefined;
			destination(root, name);
			if (type === "0") {
				write(root, name, bytes.subarray(dataStart, dataStart + size));
				if (process.platform !== "win32")
					fs.chmodSync(
						destination(root, name),
						parseInt(text(100, 8).trim() || "644", 8) & 0o777,
					);
			} else if (type === "1" || type === "2") {
				const target = text(157, 100);
				if (
					!target ||
					target.startsWith("/") ||
					target.includes("\\") ||
					/^[A-Za-z]:/.test(target)
				)
					throw new Error(`Unsafe archive link: ${name}`);
				const resolved =
					type === "2"
						? path.posix.normalize(
								path.posix.join(path.posix.dirname(name), target),
							)
						: target;
				destination(root, resolved);
				links.push({ name, target: resolved });
			} else if (type !== "5")
				throw new Error(`Unsupported TAR entry type ${type}: ${name}`);
		}
		offset = dataStart + Math.ceil(size / 512) * 512;
	}
	// Materialize internal file links after their targets have been extracted.
	// No filesystem symlinks are created, so later archive entries cannot follow one.
	while (links.length) {
		let resolved = false;
		for (let index = links.length - 1; index >= 0; index--) {
			const link = links[index];
			const source = destination(root, link.target);
			if (!fs.existsSync(source)) continue;
			const metadata = fs.statSync(source);
			if (!metadata.isFile())
				throw new Error(`Archive link target must be a file: ${link.name}`);
			const target = destination(root, link.name);
			fs.mkdirSync(path.dirname(target), { recursive: true });
			// A hard link preserves file contents and permissions without expanding
			// large executable aliases into duplicate files in the staging area.
			fs.linkSync(source, target);
			links.splice(index, 1);
			resolved = true;
		}
		if (!resolved) throw new Error(`Unresolved archive link: ${links[0].name}`);
	}
}

export function extract(
	root: string,
	name: string,
	bytes: Buffer,
	executableName: string,
) {
	if (bytes.length > MAX_SIZE) throw new Error("Download exceeds size limit");
	if (name.endsWith(".zip")) return unzip(root, bytes);
	if (name.endsWith(".tar.gz") || name.endsWith(".tgz"))
		return untar(root, bytes);
	if (
		typeof executableName !== "string" ||
		executableName !== path.basename(executableName)
	)
		throw new Error(`Unsupported asset: ${name}`);
	write(root, executableName, bytes);
}
