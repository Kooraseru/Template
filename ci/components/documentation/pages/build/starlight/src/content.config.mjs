import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { docsSchema } from '@astrojs/starlight/schema';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Content belongs to the repository, not the Astro application.
const documentation = resolve(dirname(fileURLToPath(import.meta.url)), '../../../../../../../content/docs');

export const collections = {
  docs: defineCollection({
    loader: glob({
      base: documentation,
      pattern: ['**/*.{md,mdx}', '!repository/**'],
    }),
    schema: docsSchema(),
  }),
};
