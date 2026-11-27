"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const documentation = path.join(root, "content/docs");
const repositoryTemplates = path.join(documentation, "repository");

function sitePages(directory = documentation, pages = []) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const location = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (location !== repositoryTemplates) sitePages(location, pages);
    } else if (entry.isFile() && /\.(?:mdx?|api\.yaml)$/.test(entry.name)) {
      pages.push(location);
    }
  }
  return pages.sort();
}

test("published documentation has predictable Markdown metadata", () => {
  const pages = sitePages();
  assert.ok(pages.includes(path.join(documentation, 'index.md')), 'Documentation requires a homepage');
  assert.ok(pages.length > 0);
  for (const file of pages) {
    const source = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
    if(file.endsWith(".api.yaml")){
      const data=require("../../dependencies/managed/npm/node_modules/yaml").parse(source);
      assert.ok(data.name&&data.summary&&data.type);continue;
    }
    const metadata = source.match(/^---\ntitle: ([^\n]+)\ndescription: ([^\n]+)\n(?:sidebar:\n  order: \d+\n)?---\n/);
    assert.ok(metadata, file + ": requires title/description YAML front matter");
    assert.ok(metadata[1].trim() && metadata[2].trim(), file + ": empty metadata");
    assert.equal((source.match(/^# /gm) || []).length, 0, file + ": The renderer renders the frontmatter title as H1");
    // The renderer emits directory URLs, not raw Markdown source filenames.
    const route = '/' + path.relative(documentation, file).replace(/\\/g, '/')
      .replace(/(?:^|\/)index\.mdx?$/, '/').replace(/\.mdx?$/, '/').replace(/^\/+/, '');
    for (const match of source.matchAll(/\]\(([^)\s]+)\)/g)) {
      const link = match[1];
      if (/^(?:[a-z][a-z0-9+.-]*:|#|\/\/)/i.test(link)) continue;
      assert.ok(!/\.md(?:$|[?#])/.test(link), file + ": raw Markdown URL " + link);
      if (!link.startsWith('.')) continue;
      const resolved = new URL(link, 'https://docs.example' + route);
      const target = resolved.pathname.replace(/^\//, '').replace(/\/$/, '');
      const candidates = [path.join(documentation, target + '.md'), path.join(documentation, target, 'index.md'), path.join(documentation, target + '.mdx'), path.join(documentation, target, 'index.mdx'), path.join(documentation, target + '.api.yaml')];
      assert.ok(candidates.some(candidate => pages.includes(candidate)), file + ": broken documentation route " + link);
    }
  }
});

test("source content is top-level and legacy docs directories are gone", () => {
  assert.ok(fs.existsSync(path.join(root, "content/images")));
  assert.ok(!fs.existsSync(path.join(root, "content/i18n")));
  assert.ok(fs.existsSync(path.join(repositoryTemplates, "README.md")));
  assert.ok(!fs.existsSync(path.join(root, ".github/docs")));
  assert.ok(!fs.existsSync(path.join(root, "content/templates")));
});

test("builders stage the authored docs into branch and Pages outputs", () => {
  const site = fs.readFileSync(path.join(root, ".github/components/documentation/pages/build/starlight/build.cjs"), "utf8");
  const branches = fs.readFileSync(path.join(root, ".github/components/governance/branches/build/branchBuilder.luau"), "utf8");
  assert.match(site, /tools\.documentation/);
  const dependency = JSON.parse(fs.readFileSync(path.join(root,"dependencies/dependencies.json"),"utf8")).dependencies["tools.documentation"];
  assert.match(dependency.options.commit,/^[a-f0-9]{40}$/);
  assert.equal(dependency.options.sourcePath,"package");
  assert.equal(dependency.options.repository,"Kooraseru-Hub/Documentation");
  assert.ok(fs.existsSync(path.join(root, "content/theme.css")));
  assert.match(branches, /CONTENT_ROOT = "content\/docs\/repository"/);
  assert.doesNotMatch(branches, /TagRenderer|overlayTranslations/);
  assert.match(branches, /OUTPUT_ROOT = "build\/github\/branches"/);
});
