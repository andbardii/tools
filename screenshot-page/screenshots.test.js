const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { options, capture } = require('./screenshots');

test('CLI rejects malformed input before opening browser', () => {
  for (const args of [[], ['file:///tmp/test'], ['https://example.com', '--width', '-1'],
    ['https://example.com', '--timeout', '0'], ['https://example.com', '--output', 'image.gif'],
    ['https://example.com', '--unknown']]) assert.throws(() => options(args));
  assert.equal(options(['--help']).help, true);
});

test('captures long responsive page, lazy content, viewport and HTTP errors', async () => {
  const server = http.createServer((req, res) => {
    if (req.url === '/missing') { res.writeHead(404); res.end('Missing'); return; }
    res.setHeader('Content-Type', 'text/html');
    res.end(`<style>body{margin:0;height:2400px}#lazy{position:absolute;top:2200px}</style>
      <div id="ready">Fixture</div><div id="lazy">Lazy</div><script>
      const observer = new IntersectionObserver(([entry]) => {
        if(entry.isIntersecting){document.body.style.height='3000px';observer.disconnect();}
      });observer.observe(document.querySelector('#lazy'));</script>`);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'screenshot-test-'));
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    const config = options([url, '--width', '800', '--height', '600', '--scroll', '--selector', '#ready', '--output', path.join(dir, 'nested', 'full.png')]);
    await capture(config);
    const full = await fs.readFile(config.output);
    assert.equal(full.readUInt32BE(16), 800);
    assert.equal(full.readUInt32BE(20), 3000);
    config['viewport-only'] = true;
    config.output = path.join(dir, 'viewport.png');
    await capture(config);
    const viewport = await fs.readFile(config.output);
    assert.equal(viewport.readUInt32BE(20), 600);
    await assert.rejects(capture({ ...config, url: `${url}/missing` }), /HTTP 404/);
    await assert.rejects(capture({ ...config, selector: '#absent', timeout: 500 }), /Waiting for selector/);
    await assert.rejects(capture({ ...config, output: path.join(config.output, 'bad.png') }), /EEXIST|ENOTDIR/);
  } finally {
    await new Promise(resolve => server.close(resolve));
    await fs.rm(dir, { recursive: true, force: true });
  }
});
