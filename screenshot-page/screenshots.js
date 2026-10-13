#!/usr/bin/env node
const { parseArgs } = require('node:util');
const path = require('node:path');
const fs = require('node:fs/promises');

const help = `Uso: node screenshots.js URL [opzioni]
  --output PATH       File PNG, JPEG o WebP (default: screenshot.png)
  --width N           Larghezza viewport (default: 1440)
  --height N          Altezza viewport (default: 900)
  --timeout N         Timeout operazioni in ms (default: 30000)
  --delay N           Attesa aggiuntiva in ms (default: 0)
  --selector CSS      Attende un elemento visibile
  --viewport-only     Cattura solo il viewport
  --scroll            Scorre per attivare contenuti lazy (max 100 passi)
  --help              Mostra questa guida`;

function options(args) {
  const { values, positionals } = parseArgs({ args, allowPositionals: true, options: {
    output: { type: 'string', default: 'screenshot.png' },
    width: { type: 'string', default: '1440' }, height: { type: 'string', default: '900' },
    timeout: { type: 'string', default: '30000' }, delay: { type: 'string', default: '0' },
    selector: { type: 'string' }, 'viewport-only': { type: 'boolean' },
    scroll: { type: 'boolean' }, help: { type: 'boolean' },
  } });
  if (values.help) return { help: true };
  if (positionals.length !== 1) throw new Error('Specifica un solo URL. Usa --help per le opzioni.');
  let url;
  try { url = new URL(positionals[0]); } catch { throw new Error('URL non valido: usa http:// o https://.'); }
  if (!['http:', 'https:'].includes(url.protocol)) throw new Error('Sono ammessi solo URL HTTP e HTTPS.');
  for (const key of ['width', 'height', 'timeout', 'delay']) {
    if (!/^\d+$/.test(values[key])) throw new Error(`--${key} deve essere un intero.`);
    values[key] = Number(values[key]);
    const max = ['width', 'height'].includes(key) ? 10000 : 300000;
    if (!Number.isSafeInteger(values[key]) || values[key] < (key === 'delay' ? 0 : 1) || values[key] > max)
      throw new Error(`--${key} fuori intervallo (massimo ${max}).`);
  }
  if (!/\.(png|jpe?g|webp)$/i.test(values.output)) throw new Error('--output deve avere estensione .png, .jpg, .jpeg o .webp.');
  return { ...values, url: url.href, output: path.resolve(values.output) };
}

async function capture(config) {
  const puppeteer = require('puppeteer');
  let browser;
  try {
    await fs.mkdir(path.dirname(config.output), { recursive: true });
    browser = await puppeteer.launch({ timeout: config.timeout });
    const page = await browser.newPage();
    page.setDefaultTimeout(config.timeout);
    await page.setViewport({ width: config.width, height: config.height, deviceScaleFactor: 1 });
    const response = await page.goto(config.url, { waitUntil: 'load', timeout: config.timeout });
    if (response && response.status() >= 400) throw new Error(`La pagina ha risposto HTTP ${response.status()}.`);
    if (config.selector) await page.waitForSelector(config.selector, { visible: true });
    if (config.scroll) {
      const completed = await page.evaluate(async () => {
        for (let step = 0; step < 100; step++) {
          const before = window.scrollY;
          window.scrollBy(0, Math.max(1, window.innerHeight * 0.8));
          await new Promise(resolve => setTimeout(resolve, 100));
          if (window.scrollY === before) { window.scrollTo(0, 0); return true; }
        }
        window.scrollTo(0, 0);
        return false;
      });
      if (!completed) console.warn('Limite di scorrimento raggiunto: contenuti infiniti potrebbero essere incompleti.');
    }
    if (config.delay) await new Promise(resolve => setTimeout(resolve, config.delay));
    await page.screenshot({ path: config.output, fullPage: !config['viewport-only'] });
    return config.output;
  } finally {
    if (browser) await browser.close();
  }
}

async function main() {
  try {
    const config = options(process.argv.slice(2));
    if (config.help) { console.log(help); return; }
    console.log(`Screenshot salvato: ${await capture(config)}`);
  } catch (error) {
    console.error(`Errore: ${error.message}`);
    process.exitCode = 1;
  }
}
if (require.main === module) main();
module.exports = { options, capture };
