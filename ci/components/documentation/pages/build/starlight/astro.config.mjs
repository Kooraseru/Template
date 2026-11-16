import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(here, '../../../../../..');
const repository = process.env.GITHUB_REPOSITORY || '';
const [owner, name] = repository.split('/');
const title = process.env.DOCS_TITLE || name || 'Project';
const projectSite = Boolean(owner && name);
const defaultBase = projectSite && name.toLowerCase() !== (owner + '.github.io').toLowerCase()
  ? '/' + name + '/' : '/';
const base = process.env.DOCS_BASE || defaultBase;
const site = process.env.DOCS_SITE || (owner
  ? 'https://' + owner.toLowerCase() + '.github.io'
  : 'https://example.com');
if (!/^\/(?:[A-Za-z0-9._~-]+\/)*$/.test(base)) {
  throw new Error('DOCS_BASE must be a root-relative directory path ending in /');
}

export default defineConfig({
  srcDir: resolve(here, 'src'),
  outDir: resolve(repositoryRoot, 'build/github/pages'),
  cacheDir: resolve(repositoryRoot, 'build/cache/astro'),
  site,
  base,
  integrations: [starlight({
    title,
    // Omit sidebar: Starlight derives it from the authored Markdown tree.
    editLink: projectSite ? { baseUrl: 'https://github.com/' + repository + '/edit/source/content/docs/' } : undefined,
  })],
});
