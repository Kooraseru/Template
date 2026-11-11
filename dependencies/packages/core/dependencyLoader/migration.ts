import fs from "node:fs";
import path from "node:path";
import { withStage } from "./publication.ts";

// Copy once under the old loader's lock. Keep the original tree as a recovery copy.
// Publication by rename ensures interrupted copies are never treated as installed.
export async function migrateLayout(workspace: string) {
	const old = path.join(workspace, "build/dependencies");
	const managed = path.join(workspace, "dependencies/managed");
	if (fs.existsSync(old) && !fs.existsSync(managed)) {
		await withStage(old, async () => {
			if (fs.existsSync(managed)) return;
			fs.mkdirSync(path.dirname(managed), { recursive: true });
			const staging = fs.mkdtempSync(path.join(path.dirname(managed), ".managed-migration-"));
			try {
				fs.cpSync(old, staging, {
					recursive: true, verbatimSymlinks: true,
					filter: source => !/^\.loader-(lock|stage-|owner-)/.test(path.relative(old, source).split(path.sep)[0]),
				});
				fs.renameSync(staging, managed);
			} finally { fs.rmSync(staging, { recursive: true, force: true }); }
		});
	}
	const selection = path.join(workspace, "build/run/editor-problems");
	const destination = path.join(workspace, ".workspace/editor-problems");
	if (fs.existsSync(selection)) {
		fs.mkdirSync(path.dirname(destination), { recursive: true });
		fs.cpSync(selection, destination, { recursive: true, force: false, errorOnExist: false });
	}
}
