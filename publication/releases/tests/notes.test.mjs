import test from 'node:test';
import assert from 'node:assert/strict';
import { releaseNotes } from '../notes.mjs';

const repo = 'https://github.com/example/project';
const selection = { from: 'beginning', source_sha: 'a'.repeat(40) };
test('notes deduplicate PRs, preserve direct changes, and credit only coauthors', async () => {
  const pr = { number: 17, title: 'Fix behavior', user: { login: 'author' }, merged_at: '2026-01-01',
    merge_commit_sha: 'merge', base: { ref: 'source', repo: { html_url: repo } } };
  const data = { commits: ['merge','member','direct'].map(sha => ({ sha, subject: sha, url: repo + '/commit/' + sha })),
    contributors: ['Ordinary author'], coauthors: ['Coauthor'] };
  const api = { pages: async route => route.includes('direct') ? [] : [pr, { ...pr, number: 18, merged_at: null }] };
  const body = await releaseNotes(selection, data, repo, api);
  assert.equal(body.match(/\[#17\]/g).length, 1);
  assert.ok(body.includes('by @author in [#17]'));
  assert.ok(body.includes('[direct]'));
  assert.ok(!body.includes('[member]'));
  assert.ok(body.includes('**Full Changelog**'));
  assert.ok(body.includes('Co-authored-by: Coauthor'));
  for (const text of ['Ordinary author','## Contributors','·','Selected source commit']) assert.ok(!body.includes(text));
});
test('empty ranges have no invented PRs or coauthor footer', async () => {
  const body = await releaseNotes(selection, { commits: [], coauthors: [] }, repo, null);
  assert.ok(body.includes('No changes in this range.'));
  assert.ok(!body.includes('Co-authored-by:'));
});
