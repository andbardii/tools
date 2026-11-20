import http from 'node:http';
import { readFile, readdir, stat, realpath, mkdir, writeFile, access } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import path from 'node:path';

const root = path.resolve(fileURLToPath(new URL('./public/', import.meta.url)));
const port = Number(process.env.ART_PORT || 4322);
const types = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png'};
const imageTypes = {'.jpg':'image/jpeg','.jpeg':'image/jpeg','.png':'image/png','.webp':'image/webp'};

// Cataloghi: cartelle di foto collegate. Si leggono e basta, non si scrive mai nelle cartelle.
const configDir = path.join(os.homedir(), '.config', 'art');
const configFile = path.join(configDir, 'cataloghi.json');
const cacheDir = path.join(os.homedir(), '.cache', 'art', 'anteprime');

const json = (res, code, body) => { res.writeHead(code, {'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}); res.end(JSON.stringify(body)); };
const isImage = name => !name.startsWith('.') && path.extname(name).toLowerCase() in imageTypes;

async function leggiCataloghi() {
  try { const lista = JSON.parse(await readFile(configFile, 'utf8')); return Array.isArray(lista) ? lista : []; } catch { return []; }
}
async function salvaCataloghi(lista) { await mkdir(configDir, { recursive: true }); await writeFile(configFile, JSON.stringify(lista, null, 1)); }
const idDi = percorso => createHash('sha1').update(percorso).digest('hex').slice(0, 10);

// Risolve una sottocartella o un file dentro un catalogo, rifiutando tutto ciò che esce dalla cartella collegata (anche con link simbolici).
async function dentro(catalogo, rel = '') {
  const base = await realpath(catalogo.percorso);
  const target = await realpath(path.resolve(base, '.' + path.sep + rel));
  if (target !== base && !target.startsWith(base + path.sep)) throw Object.assign(new Error('fuori dal catalogo'), { code: 403 });
  return { base, target };
}

function scegliCartella() {
  return new Promise((resolve, reject) => {
    execFile('osascript', ['-e', 'POSIX path of (choose folder with prompt "Scegli la cartella di foto da collegare ad Art")'], { timeout: 300000 }, (err, out) => {
      if (err) return reject(Object.assign(new Error('Scelta annullata'), { code: 499 }));
      resolve(out.trim().replace(/\/$/, ''));
    });
  });
}

async function anteprima(file, mtime) {
  const chiave = createHash('sha1').update(file + ':' + mtime).digest('hex');
  const out = path.join(cacheDir, chiave + path.extname(file).toLowerCase().replace('.webp', '.png'));
  try { await access(out); return out; } catch {}
  await mkdir(cacheDir, { recursive: true });
  await new Promise((resolve, reject) => execFile('sips', ['-Z', '420', file, '--out', out], { timeout: 20000 }, e => e ? reject(e) : resolve()));
  return out;
}

async function api(req, res, url) {
  const parti = url.pathname.split('/').filter(Boolean).slice(1); // dopo "api"
  if (parti[0] !== 'cataloghi') return json(res, 404, { errore: 'Non trovato' });
  const lista = await leggiCataloghi();
  const metodo = req.method;

  if (parti.length === 1 && metodo === 'GET') {
    return json(res, 200, { cataloghi: lista.map(({ id, nome }) => ({ id, nome })) });
  }

  // Le modifiche richiedono l'intestazione X-Art: nessun sito esterno può scrivere dal browser.
  const scrittura = metodo !== 'GET';
  if (scrittura && req.headers['x-art'] !== '1') return json(res, 403, { errore: 'Richiesta non valida' });

  if (parti.length === 1 && metodo === 'POST') {
    let corpo = '';
    for await (const pezzo of req) { corpo += pezzo; if (corpo.length > 10000) return json(res, 413, { errore: 'Richiesta troppo grande' }); }
    let dati = {}; try { dati = JSON.parse(corpo || '{}'); } catch { return json(res, 400, { errore: 'JSON non valido' }); }
    let percorso = dati.scegli ? await scegliCartella() : String(dati.percorso || '').trim();
    if (percorso.startsWith('~/')) percorso = path.join(os.homedir(), percorso.slice(2));
    if (!path.isAbsolute(percorso)) return json(res, 400, { errore: 'Serve un percorso assoluto' });
    let vero; try { vero = await realpath(percorso); if (!(await stat(vero)).isDirectory()) throw 0; } catch { return json(res, 400, { errore: 'Cartella non trovata' }); }
    const id = idDi(vero);
    if (!lista.some(c => c.id === id)) lista.push({ id, nome: String(dati.nome || path.basename(vero)).slice(0, 80), percorso: vero });
    await salvaCataloghi(lista);
    return json(res, 200, { id });
  }

  const catalogo = lista.find(c => c.id === parti[1]);
  if (!catalogo) return json(res, 404, { errore: 'Catalogo non trovato' });

  if (parti.length === 2 && metodo === 'DELETE') { // scollega: la cartella non viene toccata
    await salvaCataloghi(lista.filter(c => c.id !== catalogo.id));
    return json(res, 200, { ok: true });
  }

  const rel = url.searchParams.get('p') || '';
  if (parti[2] === 'cartella' && metodo === 'GET') {
    const { base, target } = await dentro(catalogo, rel);
    const voci = await readdir(target, { withFileTypes: true });
    const cartelle = [], file = [];
    for (const v of voci) {
      if (v.name.startsWith('.')) continue;
      const figlio = path.join(target, v.name);
      let s; try { s = await stat(figlio); } catch { continue; }
      const relFiglio = path.relative(base, figlio);
      if (s.isDirectory()) cartelle.push({ nome: v.name, rel: relFiglio });
      else if (isImage(v.name)) file.push({ nome: v.name, rel: relFiglio, byte: s.size, mtime: Math.round(s.mtimeMs) });
    }
    const ord = (a, b) => a.nome.localeCompare(b.nome, 'it', { numeric: true });
    return json(res, 200, { rel: path.relative(base, target), cartelle: cartelle.sort(ord), file: file.sort(ord) });
  }

  if ((parti[2] === 'file' || parti[2] === 'anteprima') && metodo === 'GET') {
    const { target } = await dentro(catalogo, rel);
    const s = await stat(target);
    if (!s.isFile() || !isImage(target)) return json(res, 404, { errore: 'Non è un\'immagine' });
    let invio = target;
    if (parti[2] === 'anteprima') { try { invio = await anteprima(target, s.mtimeMs); } catch { invio = target; } }
    const tipo = imageTypes[path.extname(invio).toLowerCase()];
    res.writeHead(200, { 'Content-Type': tipo, 'Content-Length': (await stat(invio)).size, 'Cache-Control': 'private, max-age=3600', 'X-Content-Type-Options': 'nosniff' });
    return createReadStream(invio).pipe(res);
  }
  return json(res, 404, { errore: 'Non trovato' });
}

const hostOk = host => [`127.0.0.1:${port}`, `localhost:${port}`].includes(String(host || '').toLowerCase()); // contro il DNS rebinding

const server = http.createServer(async (req, res) => {
  try {
    if (!hostOk(req.headers.host)) { res.writeHead(403); return res.end(); }
    const url = new URL(req.url, 'http://localhost');
    const pathname = decodeURIComponent(url.pathname);
    if (pathname === '/health') { res.writeHead(200,{'Content-Type':'application/json'}); return res.end('{"app":"art"}'); }
    if (pathname.startsWith('/api/')) {
      try { return await api(req, res, url); }
      catch (e) { return json(res, e.code === 403 || e.code === 499 ? e.code : e.code === 'ENOENT' ? 404 : 500, { errore: e.code === 403 ? 'Percorso non consentito' : e.code === 499 ? e.message : e.code === 'ENOENT' ? 'Non trovato' : 'Errore interno' }); }
    }
    const target = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!target.startsWith(root + path.sep)) {res.writeHead(403); return res.end();}
    const data = await readFile(target);
    res.writeHead(200,{'Content-Type':types[path.extname(target)] || 'application/octet-stream','X-Content-Type-Options':'nosniff'});res.end(data);
  } catch {res.writeHead(404);res.end('Non trovato');}
});
server.listen(port,'127.0.0.1',()=>console.log(`Art: http://localhost:${server.address().port}`));
server.on('error',error=>{console.error(error.message);process.exit(1);});
