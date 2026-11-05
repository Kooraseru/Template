// rule-runner=node
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const extensions = new Set(['.js', '.cjs', '.mjs']);
const excluded = new Set(['.git', 'build', 'node_modules']);

function syntaxError(file) {
	const result = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8' });
	if (!result.error && result.status === 0) return undefined;
	const details = result.stderr || String(result.error || `Node exited with status ${result.status}`);
	const location = details.match(/^(.*):([0-9]+)(?::[0-9]+)?\r?\n/m);
	const message = details.match(/(?:SyntaxError|Error):[^\r\n]*/);
	return {
		line: location ? Number(location[2]) : 1,
		message: `JavaScript ${message ? message[0] : details.replace(/[\r\n]+/g, ' ')}`,
	};
}

function scan(directory) {
	const files = [];
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		if (entry.isSymbolicLink()) continue;
		const filename = path.join(directory, entry.name);
		if (entry.isDirectory()) {
			if (!excluded.has(entry.name)) files.push(...scan(filename));
		} else if (entry.isFile() && extensions.has(path.extname(entry.name))) files.push(filename);
	}
	return files;
}

if (process.argv[2] === '--test') {
	const fixtures = path.join(__dirname, 'tests');
	if (syntaxError(path.join(fixtures, 'valid.js'))) throw new Error('valid JavaScript fixture was rejected');
	if (!syntaxError(path.join(fixtures, 'invalid.js'))) throw new Error('invalid JavaScript fixture was accepted');
	process.exit(0);
}

const root = path.resolve(process.argv.at(-1) || '.');
for (const file of scan(root).sort()) {
	const finding = syntaxError(file);
	if (finding) console.log(`${file}:${finding.line}:1: error: ${finding.message}`);
}
