import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { command, git, write, sha256, canonical, sourceTip, validateChannels, cacheEligible, artifactEligible, verifyDistribution, policy } from './core.mjs';

const read = file => JSON.parse(fs.readFileSync(file));
const gh = args => JSON.parse(command('gh', ['api', ...args]));
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
  const controllerFiles = git(['ls-files', 'ci', '.github/actions']).split('\n')
    .filter(file => fs.existsSync(file) && !/README|\.md$|config\.toml$|channels\.toml$|records\//.test(file));
  // Include untracked implementation files during local previews too.
  const extra = git(['ls-files', '--others', '--exclude-standard', 'ci', '.github/actions']).split('\n')
    .filter(file => file && !controllerFiles.includes(file) && !/README|\.md$|config\.toml$|channels\.toml$|records\//.test(file));
  const controllerHash = sha256(canonical([...controllerFiles, ...extra].sort().map(file => [file, sha256(fs.readFileSync(file))])));
  const imageArtifact = (definition, recipes) => 'image-' + definition.name + '-' + sha256(canonical({ definition, recipes })).slice(0, 24);
  for (const entry of plan.builds) {
    entry.fingerprint = sha256(canonical({ controllerHash, build: entry.build, target: {
      name: entry.name, runner: entry.runner, target: entry.target, profile: entry.profile, environment: entry.environment,
      probes: entry.probes, rust_version: entry.rust_version, msvc_arch: entry.msvc_arch,
    }, image: entry.image_definition || null, recipes: entry.recipes }));
    if (entry.image_definition) entry.image_artifact = imageArtifact(entry.image_definition, entry.recipes);
    delete entry.recipes;
    entry.cache_run = '';
    if (!entry.current && process.env.ACT !== 'true' && process.env.GITHUB_ACTIONS === 'true' && process.env.GH_TOKEN) {
      const repo = process.env.GITHUB_REPOSITORY;
      const runs = gh([`repos/${repo}/actions/workflows/ci.yml/runs?event=push&branch=source&head_sha=${entry.source_sha}&status=success&per_page=${policy.cache_run_limit}`]).workflow_runs;
      for (const run of runs.filter(run => cacheEligible(run, entry.source_sha, repo))) {
        const artifacts = gh([`repos/${repo}/actions/runs/${run.id}/artifacts?per_page=100`]).artifacts;
        if (artifacts.some(artifact => artifactEligible(artifact, entry.artifact))) { entry.cache_run = String(run.id); break; }
      }
    }
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
  let reused = false;
  if (entry.cache_run && fs.existsSync('build/artifacts/provenance.json')) {
    try { verifyDistribution('build/artifacts', entry); reused = true; }
    catch (error) { console.warn(`Cached artifact rejected; rebuilding: ${error.message}`); fs.rmSync('build/artifacts', { recursive: true, force: true }); }
  }
  fs.mkdirSync(directory, { recursive: true });
  write(`${directory}/build-spec.json`, entry);
  const source = path.resolve('build/tmp/source', entry.source_sha);
  if (!reused) {
    // Standalone snapshot, no worktree links or dependence on ignored local files.
    fs.rmSync(source, { recursive: true, force: true });
    fs.mkdirSync(source, { recursive: true });
    const archive = path.resolve(`${directory}/source.tar`);
    git(['archive', '--format=tar', `--output=${archive}`, entry.source_sha]);
    command('tar', ['-xf', archive, '-C', source]);
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
