#!/usr/bin/env node
'use strict';
const { SitemapStream, streamToPromise } = require('sitemap');
const { readFile, mkdir, writeFile } = require('node:fs/promises');
const path = require('node:path');

const help = `Uso: node sitemapgenerator.js --hostname https://example.com --input urls.json [--output public/sitemap.xml]
L'input è un array JSON di percorsi/URL o oggetti {url, lastmod, changefreq, priority}.
`;

function parseArgs(args) {
  const options = { output: 'sitemap.xml' };
  const seen = new Set();
  for (let i = 0; i < args.length; i++) {
    const key = args[i];
    if (!['--hostname', '--input', '--output'].includes(key)) throw new Error(`Opzione sconosciuta: ${key}`);
    if (!args[i + 1] || args[i + 1].startsWith('--')) throw new Error(`Valore mancante: ${key}`);
    if (seen.has(key)) throw new Error(`Opzione ripetuta: ${key}`);
    seen.add(key);
    options[key.slice(2)] = args[++i];
  }
  if (!options.hostname || !options.input) throw new Error('--hostname e --input sono obbligatori');
  return options;
}

function normalizeLinks(input, hostname) {
  let base;
  try { base = new URL(hostname); } catch { throw new Error('Hostname non valido'); }
  if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password || base.pathname !== '/' || base.search || base.hash) {
    throw new Error('Hostname deve essere una origine HTTP/HTTPS senza percorso, credenziali, query o frammenti');
  }
  if (!Array.isArray(input) || !input.length) throw new Error('Input deve essere un array JSON non vuoto');
  if (input.length > 50000) throw new Error('Una sitemap può contenere al massimo 50000 URL');
  const seen = new Set();
  return input.map((entry, index) => {
    const item = typeof entry === 'string' ? { url: entry } : entry;
    if (!item || typeof item !== 'object' || Array.isArray(item) || typeof item.url !== 'string' || !item.url.trim()) throw new Error(`URL mancante alla posizione ${index}`);
    const unknown = Object.keys(item).filter(key => !['url', 'lastmod', 'changefreq', 'priority'].includes(key));
    if (unknown.length) throw new Error(`Campi non supportati: ${unknown.join(', ')}`);
    if (/[\x00-\x1f\x7f]/.test(item.url)) throw new Error('URL contiene caratteri di controllo');
    let url;
    try { url = new URL(item.url.trim(), base); } catch { throw new Error(`URL non valido: ${item.url}`); }
    if (!['http:', 'https:'].includes(url.protocol) || url.origin !== base.origin || url.username || url.password) throw new Error(`URL esterno o protocollo non valido: ${item.url}`);
    url.hash = '';
    if (item.changefreq !== undefined && !['always', 'hourly', 'daily', 'weekly', 'monthly', 'yearly', 'never'].includes(item.changefreq)) throw new Error(`changefreq non valido: ${item.changefreq}`);
    if (item.priority !== undefined && (typeof item.priority !== 'number' || !Number.isFinite(item.priority) || item.priority < 0 || item.priority > 1)) throw new Error('priority deve essere un numero tra 0 e 1');
    if (item.lastmod !== undefined && (typeof item.lastmod !== 'string' || !/^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))?$/.test(item.lastmod) || !Number.isFinite(Date.parse(item.lastmod)) || new Date(item.lastmod.slice(0, 10)).toISOString().slice(0, 10) !== item.lastmod.slice(0, 10))) throw new Error('lastmod deve essere una data ISO valida');
    const result = { ...item, url: url.href };
    if (seen.has(result.url)) return null;
    seen.add(result.url);
    return result;
  }).filter(Boolean);
}

async function main(args) {
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) { process.stdout.write(help); return; }
  const options = parseArgs(args);
  const links = normalizeLinks(JSON.parse(await readFile(options.input, 'utf8')), options.hostname);
  const sitemap = new SitemapStream();
  const xmlPromise = streamToPromise(sitemap);
  for (const link of links) sitemap.write(link);
  sitemap.end();
  const xml = await xmlPromise;
  if (xml.length > 50 * 1024 * 1024) throw new Error('La sitemap supera il limite di 50 MB');
  await mkdir(path.dirname(path.resolve(options.output)), { recursive: true });
  await writeFile(options.output, xml);
  process.stdout.write(`Sitemap scritta: ${path.resolve(options.output)} (${links.length} URL)\n`);
}
if (require.main === module) main(process.argv.slice(2)).catch(error => { process.stderr.write(`Errore: ${error.message}\n`); process.exitCode = 1; });
module.exports = { main, normalizeLinks, parseArgs };
