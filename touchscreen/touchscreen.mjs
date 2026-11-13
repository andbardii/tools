#!/usr/bin/env node
// Avvia/ferma il driver touch (start | stop | status | list). Compila Swift al primo avvio.
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync, existsSync, statSync, mkdirSync} from 'node:fs';
import readline from 'node:readline/promises';
import {fileURLToPath} from 'node:url';
import os from 'node:os';
import path from 'node:path';
const dir = fileURLToPath(new URL('.', import.meta.url));
const src = path.join(dir, 'driver.swift');
const app = path.join(os.homedir(), 'Applications', 'Touchscreen.app'), bin = path.join(app, 'Contents', 'MacOS', 'Touchscreen');
const configFile = path.join(os.homedir(), '.config', 'touchscreen.json');
const log = path.join(os.tmpdir(), `touchscreen-${process.getuid()}.log`);

function ownedPid() {
  try { return Number(execFileSync('pgrep', ['-f', bin], {encoding: 'utf8'}).split('\n')[0]) || null; }
  catch { return null; }
}
// App vera e propria (non un binario nudo): in Privacy e sicurezza compare come "Touchscreen".
const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Touchscreen</string>
<key>CFBundleDisplayName</key><string>Touchscreen</string>
<key>CFBundleIdentifier</key><string>it.andbardii.tools.touchscreen</string>
<key>CFBundleExecutable</key><string>Touchscreen</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
`;
function build() {
  if (existsSync(bin) && statSync(bin).mtimeMs >= statSync(src).mtimeMs) return;
  console.log('Compilo il driver touch…');
  execFileSync('mkdir', ['-p', path.dirname(bin)]);
  writeFileSync(path.join(app, 'Contents', 'Info.plist'), plist);
  execFileSync('swiftc', ['-O', src, '-o', bin], {stdio: 'inherit'});
  execFileSync('codesign', ['--force', '--sign', '-', '--identifier', 'it.andbardii.tools.touchscreen', app], {stdio: 'inherit'});
}
const saved = () => { try { return JSON.parse(readFileSync(configFile, 'utf8')).screen || null; } catch { return null; } };
const save = screen => { mkdirSync(path.dirname(configFile), {recursive: true}); writeFileSync(configFile, JSON.stringify({screen}, null, 2) + '\n'); };

// Elenca gli schermi collegati e chiede quale è il touchscreen; Invio conferma quello ricordato.
async function chooseScreen(forceAsk) {
  const screens = execFileSync(bin, ['list'], {encoding: 'utf8'}).trim().split('\n')
    .map(l => ({line: l, name: (l.match(/"(.*)"\s*$/) || [])[1] || ''}));
  const known = saved();
  const remembered = screens.findIndex(s => s.name && s.name === known);
  if (!process.stdin.isTTY || !process.stdout.isTTY) return known || null;
  if (remembered >= 0 && !forceAsk) { console.log(`Schermo touch: ${screens[remembered].line}  (cambia con: run touch scegli)`); return known; }
  console.log('Schermi collegati:');
  screens.forEach((s, i) => console.log(`  ${i + 1}) ${s.line}`));
  const rl = readline.createInterface({input: process.stdin, output: process.stdout});
  try {
    for (;;) {
      const a = (await rl.question(`Quale è il touchscreen?${remembered >= 0 ? ` [${remembered + 1}]` : ''} `)).trim();
      const n = a === '' && remembered >= 0 ? remembered + 1 : Number(a);
      if (Number.isInteger(n) && n >= 1 && n <= screens.length) {
        if (!screens[n - 1].name) { console.log('Questo schermo non ha un nome: sceglierne un altro.'); continue; }
        save(screens[n - 1].name); return screens[n - 1].name;
      }
      console.log(`Scrivi un numero da 1 a ${screens.length}.`);
    }
  } catch (e) { if (e.code === 'ABORT_ERR') { console.log('\nScelta annullata.'); process.exit(1); } throw e; }
  finally { rl.close(); }
}

const action = process.argv[2] || 'start';
if (action === 'stop') {
  const pid = ownedPid();
  if (!pid) { console.log('Touchscreen non è in esecuzione.'); process.exit(0); }
  process.kill(pid, 'SIGTERM');
  console.log('Touchscreen fermato.');
} else if (action === 'status') {
  const pid = ownedPid(); console.log(pid ? `Touchscreen attivo (pid ${pid}). Log: ${log}` : 'Touchscreen fermo.');
} else if (action === 'list') {
  build(); execFileSync(bin, ['list'], {stdio: 'inherit'});
} else if (action === 'start' || action === 'scegli') {
  if (ownedPid()) { console.log('Touchscreen è già attivo (fermalo con: stop touch).'); process.exit(0); }
  build();
  const screen = await chooseScreen(action === 'scegli') || process.env.TOUCH_SCREEN;
  writeFileSync(log, '');
  const args = ['-g', '-a', app, '--stdout', log, '--stderr', log];
  if (screen) args.push('--env', `TOUCH_SCREEN=${screen}`);
  if (process.env.TOUCH_DISPLAY) args.push('--env', `TOUCH_DISPLAY=${process.env.TOUCH_DISPLAY}`);
  if (process.env.TOUCH_DEBUG) args.push('--env', 'TOUCH_DEBUG=1');
  execFileSync('open', args);
  await new Promise(r => setTimeout(r, 1200));
  const pid = ownedPid();
  if (!pid) { console.error(`Non avviato. Log: ${log}\n` + readFileSync(log, 'utf8')); process.exitCode = 1; }
  else console.log(`Touchscreen avviato (pid ${pid}).\n` + readFileSync(log, 'utf8').trim());
} else { console.error('Uso: node touchscreen.mjs [start|scegli|stop|status|list]'); process.exitCode = 1; }
