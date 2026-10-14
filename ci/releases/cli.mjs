import fs from 'node:fs';
import path from 'node:path';
import { command, git, write, sha256, canonical, sourceTip, validateChannels, verifyDistribution, policy } from './core.mjs';
import { identity } from '../receipts/core.mjs';
import { restore } from '../receipts/github.mjs';

const read = file => JSON.parse(fs.readFileSync(file));
const directory = 'build/tmp/releases';
const operation = process.argv[2];
if (operation === 'resolve') {
  const request = read(`${directory}/request.json`);
  const tip = sourceTip();
  // Checkout fetch-depth: 0 makes selected history available. Fetch a newly advanced hosted tip if necessary.
  if (process.env.ACT !== 'true' && process.env.GITHUB_ACTIONS === 'true') {
    const env = { ...process.env };
    if (env.GH_TOKEN) {
      env.GIT_CONFIG_COUNT = '1'; env.GIT_CONFIG_KEY_0 = 'http.https://github.com/.extraheader';
      env.GIT_CONFIG_VALUE_0 = 'AUTHORIZATION: basic ' + Buffer.from(`x-access-token:${env.GH_TOKEN}`).toString('base64');
    }
    git(['fetch', '--no-tags', 'origin', tip], { env });
  }
  write(`${directory}/selections.json`, request.enabled ? validateChannels(request.channels, tip) : []);
} else if (operation === 'plan') {
  const plan = read(`${directory}/inputs.json`);
  const controllerFiles = git(['ls-tree','-r','--name-only',plan.controller_sha,'ci','.github/actions','.github/workflows/ci.yml']).split('\n')
    .filter(file => file && !/README|\.md$|config\.toml$|channels\.toml$|records\//.test(file));
  const controllerHash = sha256(canonical(controllerFiles.sort().map(file => [file,
    sha256(command('git',['show',`${plan.controller_sha}:${file}`],{encoding:null}))])));
  const imageArtifact = (definition, recipes) => 'image-' + definition.name + '-' + sha256(canonical({ definition, recipes })).slice(0, 24);
  for (const entry of plan.builds) {
    entry.reuse_identity = entry.reuse_identity || 'exact_commit';
    if (!['exact_commit','source_tree'].includes(entry.reuse_identity)) throw Error('Invalid target reuse identity');
    if (entry.reproducible !== undefined && typeof entry.reproducible !== 'boolean') throw Error('Reproducible declaration must be boolean');
    const selected = identity(entry.source_sha);
    entry.tree = selected.tree;
    entry.source_manifest_sha256 = selected.source_manifest_sha256;
    entry.fingerprint = sha256(canonical({ controllerHash, build: entry.build, target: {
      name: entry.name, runner: entry.runner, target: entry.target, profile: entry.profile, environment: entry.environment,
      probes: entry.probes, rust_version: entry.rust_version, msvc_arch: entry.msvc_arch,
      reuse_identity:entry.reuse_identity, reproducible:entry.reproducible || false,
    }, image: entry.image_definition || null, recipes: entry.recipes }));
    if (entry.image_definition) entry.image_artifact = imageArtifact(entry.image_definition, entry.recipes);
    delete entry.recipes;
    entry.cache_run = '';
  }
  plan.controller_hash = controllerHash;
  const images = new Map();
  for (const image of plan.images) {
    image.artifact = imageArtifact(image.definition, image.recipes);
    delete image.definition; delete image.recipes;
    if (!images.has(image.artifact)) images.set(image.artifact, image);
  }
  plan.images = [...images.values()];
  write(`${directory}/plan.json`, plan);
  const imageMatrix = plan.images.length ? plan.images : [{ name: 'disabled', runner: 'ubuntu-latest', artifact: 'disabled', input_ref: '' }];
  const output = {
    build_matrix: JSON.stringify({ include: plan.builds }), image_matrix: JSON.stringify({ include: imageMatrix }),
    release_matrix: JSON.stringify({ include: plan.selections.length ? plan.selections.map(({ channel }) => ({ channel })) : [{ channel: 'disabled' }] }),
    images_enabled: String(plan.images.length > 0),
  };
  write(`${directory}/outputs.json`, output);
} else if (operation === 'prepare') {
  const entry = JSON.parse(process.env.CI_BUILD_SPEC);
  if (!new RegExp(policy.sha_pattern).test(entry.source_sha)) throw Error('Build source must be a full SHA');
  let reused = false;
  if (entry.accepted) {
    const target = await restore(entry,'build/artifacts');
    verifyDistribution('build/artifacts',{...entry, accepted_source_sha:target.source_sha});
    reused = true;
  }
  if (entry.cache_run && fs.existsSync('build/artifacts/provenance.json')) {
    try { verifyDistribution('build/artifacts', entry); reused = true; }
    catch (error) { console.warn(`Cached artifact rejected; rebuilding: ${error.message}`); fs.rmSync('build/artifacts', { recursive: true, force: true }); }
  }
  fs.mkdirSync(directory, { recursive: true });
  write(`${directory}/build-spec.json`, entry);
  const source = path.resolve('build/tmp/source', entry.source_sha);
  if (!reused) {
    // A standalone Git checkout preserves the selected HEAD for build commands
    // such as git describe. No worktree links, alternates, or ignored inputs.
    fs.rmSync(source, { recursive: true, force: true });
    fs.mkdirSync(source, { recursive: true });
    git(['clone', '--no-hardlinks', '--no-checkout', process.cwd(), source]);
    git(['-C', source, 'checkout', '--detach', entry.source_sha]);
    let origin = '';
    try { origin = git(['remote', 'get-url', 'origin']); } catch { /* a fixture may have no remote */ }
    if (origin) git(['-C', source, 'remote', 'set-url', 'origin', origin]);
    fs.mkdirSync(path.join(source, 'build'), { recursive: true });
  }
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `reused=${reused}\nsource_dir=${source}\n`);
  console.log(reused ? 'Verified cached distribution' : `Prepared source ${entry.source_sha}`);
} else if (operation === 'verify') {
  verifyDistribution(process.argv[3], JSON.parse(process.env.CI_BUILD_SPEC));
} else if (operation === 'assemble') {
  const { assemble } = await import('./render.mjs');
  await assemble(read(`${directory}/plan.json`));
} else if (operation === 'publish') {
  const { publish } = await import('./publish.mjs');
  await publish(process.env.RELEASE_CHANNEL);
} else if (operation === 'protect') {
  const { protect } = await import('./publish.mjs');
  await protect(process.argv[3]);
} else throw Error(`Unknown operation: ${operation}`);
