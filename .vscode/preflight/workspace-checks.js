// Discover rule checkers and report workspace findings to Preflight's VS Code diagnostic provider.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = process.cwd();
const bash = process.argv[2] || 'bash';
const excluded = new Set(['.git', 'build', 'node_modules']);

function snapshot(directory, records, checkers) {
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		if (entry.isSymbolicLink()) continue;
		const name = path.join(directory, entry.name);
		if (entry.isDirectory()) {
			if (!excluded.has(entry.name)) snapshot(name, records, checkers);
		} else {
			if (entry.isFile() && /^check\.[a-z0-9]+$/i.test(entry.name) && name.startsWith(path.join(root, 'rules') + path.sep)) checkers.push(name);
			const stat = fs.statSync(name);
			records.push(`${name}:${stat.mtimeMs}:${stat.size}`);
		}
	}
}

function scan(checkers) {
	console.log('WORKSPACE_DIAGNOSTICS_BEGIN');
	const printDiagnostics = (text, source) => {
		for (const line of text.split(/\r?\n/).filter(Boolean)) {
			const match = line.match(/^(.*):(\d+):(\d+): (error|warning): (.*)$/);
			if (!match) {
				console.log(line);
				continue;
			}
			const reportedPath = match[1].replaceAll('\\', '/');
			const isDriveAbsolute = /^[A-Za-z]:\//.test(reportedPath);
			const isUncAbsolute = reportedPath.startsWith('//');
			const resolvedPath = isDriveAbsolute || isUncAbsolute
				? reportedPath
				: path.resolve(root, reportedPath.replace(/^\.?\//, '').replace(/^\/+/, ''));
			console.log(`${resolvedPath}:${match[2]}:${match[3]}: ${match[4]}: [${source}] ${match[5]}`);
		}
	};
	// Discover rule-owned checkers by their colocated `check.<extension>` entrypoint.
	const luneBootstrap = '.github/ci/tooling/lune/bootstrap.sh';
	for (const checker of checkers) {
		const checkerDirectory = path.relative(path.join(root, 'rules'), path.dirname(checker)).split(path.sep).join('/');
		const diagnosticSource = `Rule: ${checkerDirectory}`;
		const source = fs.readFileSync(checker, 'utf8');
		const contractLine = source.split(/\r?\n/).slice(0, 12).find(line => /\brule-runner\s*=/.test(line));
		const contract = contractLine?.match(/\brule-runner\s*=\s*([^\s*]+)/)?.[1];
		if (!contract) {
			console.log(`${checker}:1:1: error: Rule checker must declare a rule-runner comment`);
			continue;
		}
		if (contract === 'lute') {
			const fixtures = path.join(path.dirname(checker), 'tests');
			const valid = path.join(fixtures, 'valid.luau');
			const invalid = path.join(fixtures, 'invalid.luau');
			if (!fs.existsSync(valid) || !fs.existsSync(invalid)) continue;
			const result = spawnSync(bash, [
				'-c', 'export PATH="/usr/bin:$PATH"; exec "$@"', 'workspace-diagnostics',
				'../../../.github/ci/tooling/lute/bootstrap.sh', 'lint', '--config', 'config.luau', '--json', valid, invalid,
			], { cwd: path.join(root, '.vscode/luau/lute'), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
			try {
				if (result.error) throw result.error;
				const output = JSON.parse(result.stdout);
				const validResult = output.items.find(file => file.uri.toLowerCase().replaceAll('\\', '/').endsWith('/valid.luau'));
				const invalidResult = output.items.find(file => file.uri.toLowerCase().replaceAll('\\', '/').endsWith('/invalid.luau'));
				if (!validResult || validResult.items.length || !invalidResult || !invalidResult.items.some(item => item.code === 'declarative_data')) {
					throw new Error('valid fixture should be clean and invalid fixture should report declarative_data');
				}
				for (const item of invalidResult.items) {
					const severity = item.severity === 1 ? 'error' : item.severity === 3 ? 'information' : item.severity === 4 ? 'hint' : 'warning';
					const line = (item.range?.start?.line ?? 0) + 1;
					const column = (item.range?.start?.character ?? 0) + 1;
					console.log(`${invalidResult.uri}:${line}:${column}: ${severity}: [${diagnosticSource}] ${item.message}`);
				}
			} catch (error) {
				console.log(`${checker}:1:1: error: Rule fixture check failed: ${String(error.message).replace(/[\r\n]+/g, ' ')}`);
			}
			continue;
		}
		const checkerPath = path.relative(root, checker).split(path.sep).join('/');
		for (const mode of ['--test', '--check']) {
			const result = contract === 'lune'
				? spawnSync(bash, [
					'-c', 'export PATH="/usr/bin:$PATH"; exec "$@"', 'workspace-diagnostics',
					luneBootstrap, 'run', checkerPath, mode, '.',
				], { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
				: contract === 'bash'
					? spawnSync(bash, [
						'-c', 'export PATH="/usr/bin:$PATH"; exec "$@"', 'workspace-diagnostics', checkerPath, mode, '.',
					], {
						cwd: root,
						encoding: 'utf8',
						maxBuffer: 16 * 1024 * 1024,
						env: { ...process.env, PREFLIGHT_BASH: bash },
					})
					: spawnSync(contract, [checkerPath, mode, '.'], { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
			if (result.error || result.status !== 0) {
			console.log(`${checker}:1:1: error: [${diagnosticSource}] Rule check ${mode} failed: ${(result.stderr || String(result.error || `exit ${result.status}`)).replace(/[\r\n]+/g, ' ')}`);
			} else if (mode === '--check') {
				printDiagnostics(result.stdout, diagnosticSource);
			}
		}
	}
	// Use the same StyLua installation and configuration as the editor formatter.
	const editorStyLua = process.env.APPDATA && path.join(process.env.APPDATA, 'Code', 'User', 'globalStorage', 'johnnymorganz.stylua', 'stylua.exe');
	const stylua = editorStyLua && fs.existsSync(editorStyLua) ? editorStyLua : 'stylua';
	const ignores = fs.readFileSync(path.join(root, '.vscode/luau/stylua/.styluaignore'), 'utf8')
		.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'))
		.flatMap(line => ['--glob', `!${line.replace(/^\//, '').replace(/\/$/, '/**')}`]);
	const format = spawnSync(stylua, [
		'--allow-hidden', '--check', '--output-format', 'Json', '--config-path',
		'.vscode/luau/stylua/.stylua.toml', '--glob', '**/*.luau', '--glob', '**/*.lua',
		...ignores, '--glob', '!.git/**', '.',
	], { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
	try {
		if (format.error) throw format.error;
		for (const line of format.stdout.split(/\r?\n/).filter(Boolean)) {
			const diff = JSON.parse(line);
			for (const mismatch of diff.mismatches || []) {
				console.log(`${path.resolve(root, diff.file)}:${Math.max(1, mismatch.original_start_line)}:1: warning: [StyLua] StyLua formatting differs from the configured style`);
			}
		}
		if (format.status !== 0 && format.status !== 1) {
			throw new Error(format.stderr.trim() || `StyLua exited with status ${format.status}`);
		}
	} catch (error) {
		console.log(`${path.join(root, '.vscode/luau/stylua/.stylua.toml')}:1:1: error: StyLua workspace check failed: ${String(error.message).replace(/[\r\n]+/g, ' ')}`);
	}
	console.log('WORKSPACE_DIAGNOSTICS_END');
}

let previous = null;
function refresh() {
	try {
		const records = [];
		const checkers = [];
		snapshot(root, records, checkers);
		const current = records.sort().join('\n');
		if (current !== previous) {
			previous = current;
			scan(checkers);
		}
	} catch (error) {
		console.log('WORKSPACE_DIAGNOSTICS_BEGIN');
		console.log(`${path.join(root, ".vscode/preflight/workspace-checks.js")}:1:1: error: Workspace scan failed: ${String(error.message).replace(/[\r\n]+/g, ' ')}`);
		console.log('WORKSPACE_DIAGNOSTICS_END');
	}
}
refresh();
if (!process.argv.includes('--once')) setInterval(refresh, 3000);
