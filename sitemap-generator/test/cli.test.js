'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtemp, writeFile, readFile, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const sax = require('sax');
const cli = path.resolve(__dirname, '../sitemapgenerator.js');
const run = args => spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });

test('CLI writes valid XML, creates directories, escapes queries and deduplicates normalized URLs', async () => {
  const dir = await mkdtemp(path.join(tmpdir(), 'sitemap-test-'));
  try {
    const input = path.join(dir, 'urls.json');
    const output = path.join(dir, 'new', 'public', 'sitemap.xml');
    await writeFile(input, JSON.stringify(['/a?x=1&y=2', '/a?x=1&y=2#section', { url: '/café', priority: 0.7, changefreq: 'weekly', lastmod: '2026-10-13' }]));
    const result = run(['--hostname', 'https://example.com', '--input', input, '--output', output]);
    assert.equal(result.status, 0, result.stderr);
    const xml = await readFile(output, 'utf8');
    const parser = sax.parser(true, { xmlns: true });
    let current = '';
    const locations = [];
    parser.onopentag = node => { current = node.local; };
    parser.ontext = text => { if (current === 'loc') locations.push(text); };
    parser.onclosetag = () => { current = ''; };
    parser.write(xml).close();
    assert.deepEqual(locations, ['https://example.com/a?x=1&y=2', 'https://example.com/caf%C3%A9']);
    assert.match(xml, /x=1&amp;y=2/);
    assert.match(xml, /<priority>0.7<\/priority>/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('CLI rejects invalid inputs and arguments with nonzero status and no output', async () => {
  const dir = await mkdtemp(path.join(tmpdir(), 'sitemap-invalid-'));
  try {
    const input = path.join(dir, 'urls.json');
    const output = path.join(dir, 'sitemap.xml');
    const cases = [JSON.stringify([{ url: '/', lastmod: '2026-02-31' }]), JSON.stringify([{ url: '/', lastmod: '2026-10-13Twhatever' }]), JSON.stringify(['/a\u0000b']), 'not json', '{}', '[]', '["javascript:alert(1)"]', '["https://evil.example/a"]', '["//evil.example/a"]', '[{"url":"/","priority":2}]', '[{"url":"/","changefreq":"sometimes"}]', '[{"url":"/","lastmod":"yesterday"}]'];
    for (const contents of cases) {
      await writeFile(input, contents);
      const result = run(['--hostname', 'https://example.com', '--input', input, '--output', output]);
      assert.equal(result.status, 1, contents);
      assert.match(result.stderr, /Errore:/);
      await assert.rejects(readFile(output), { code: 'ENOENT' });
    }
    for (const args of [['--hostname', 'https://example.com', '--input', input, '--output', output, '--output', output], [], ['--input'], ['--unknown'], ['--hostname', 'ftp://example.com', '--input', input], ['--hostname', 'https://example.com/path', '--input', input], ['--hostname', 'https://example.com', '--input', path.join(dir, 'missing')]]) {
      assert.equal(run(args).status, 1, JSON.stringify(args));
    }
    await writeFile(input, '["/"]');
    assert.equal(run(['--hostname', 'https://example.com', '--input', input, '--output', dir]).status, 1, 'write errors propagate');
    assert.equal(run(['--help']).status, 0);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
