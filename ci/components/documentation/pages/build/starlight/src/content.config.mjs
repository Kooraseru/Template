import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

// The component stages authored content/docs/ here before each build. Using
// Starlight's native loader keeps sidebar paths relative to the docs root;
// pointing glob() outside src/ produced nested '..' groups in navigation.
export const collections = {
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
};
