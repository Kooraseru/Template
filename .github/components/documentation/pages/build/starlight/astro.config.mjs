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
  // Prerendered server chunks must resolve dependencies from this package.
  outDir: resolve(here, 'dist'),
  cacheDir: resolve(repositoryRoot, 'build/cache/astro'),
  site,
  base,
  integrations: [starlight({
    title,
    favicon: '/images/favicon.png',
    // Navigation stays filesystem-generated. Authored Markdown is staged into
    // src/content/docs before each build or local preview.
    customCss: [
      './src/styles/theme/fallback.css',
      './src/styles/layout.css',
      './src/styles/typography.css',
      './src/styles/navigation.css',
      './src/styles/reference.css',
      './src/styles/project.css',
      './src/styles/theme/forced-colors.css',
    ],
    components: {
      ThemeProvider: './src/components/ThemeProvider.astro',
      ThemeSelect: './src/components/ThemeSelect.astro',
      EditLink: './src/components/EditLink.astro',
      PageTitle: './src/components/PageTitle.astro',
      TableOfContents: './src/components/TableOfContents.astro',
      MobileTableOfContents: './src/components/MobileTableOfContents.astro',
    },
    expressiveCode: {
      themes: ['github-dark'],
      useStarlightDarkModeSwitch: false,
      useStarlightUiThemeColors: false,
      useDarkModeMediaQuery: false,
      styleOverrides: {
        borderRadius: '4px',
        codePaddingBlock: '12px',
        codePaddingInline: '16px',
        codeFontSize: '14px',
        codeLineHeight: '1.4',
      },
    },
    social: repository ? [{ icon: 'github', label: 'GitHub', href: 'https://github.com/' + repository }] : [],
    // Omit sidebar: Starlight derives it from the staged Markdown tree.
    editLink: projectSite ? { baseUrl: 'https://github.com/' + repository + '/edit/source/content/docs/' } : undefined,
  })],
});
