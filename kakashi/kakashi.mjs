#!/usr/bin/env node
// Avvia/ferma Kakashi (start | stop | status | debug | selftest | log). Compila Swift al primo avvio.
import {execFileSync, spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync, existsSync, statSync, mkdirSync, unlinkSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import os from 'node:os';
import path from 'node:path';
const dir = fileURLToPath(new URL('.', import.meta.url));
const src = path.join(dir, 'kakashi.swift');
const app = path.join(os.homedir(), 'Applications', 'Kakashi.app'), bin = path.join(app, 'Contents', 'MacOS', 'Kakashi');
const log = path.join(os.tmpdir(), `kakashi-${process.getuid()}.log`);

function ownedPid() {
  try { return Number(execFileSync('pgrep', ['-f', bin], {encoding: 'utf8'}).split('\n')[0]) || null; }
  catch { return null; }
}
const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Kakashi</string>
<key>CFBundleDisplayName</key><string>Kakashi</string>
<key>CFBundleIdentifier</key><string>it.andbardii.tools.kakashi</string>
<key>CFBundleExecutable</key><string>Kakashi</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSCameraUsageDescription</key><string>Kakashi guarda la webcam per riconoscere il gesto che ti fa uscire dalla call.</string>
<key>NSAppleEventsUsageDescription</key><string>Kakashi chiude la scheda del browser (o l'app) della call quando fai il gesto.</string>
</dict></plist>
`;
function build() {
  if (existsSync(bin) && statSync(bin).mtimeMs >= statSync(src).mtimeMs) return;
  console.log('Compilo Kakashi…');
  execFileSync('mkdir', ['-p', path.dirname(bin)]);
  writeFileSync(path.join(app, 'Contents', 'Info.plist'), plist);
  execFileSync('swiftc', ['-O', '-swift-version', '5', src, '-o', bin], {stdio: 'inherit'});
  execFileSync('codesign', ['--force', '--sign', '-', '--identifier', 'it.andbardii.tools.kakashi', app], {stdio: 'inherit'});
}
// Passa all'app tutte le KAKASHI_* dell'ambiente (soglie, posizione, camera…).
function launch(extra = {}) {
  if (ownedPid()) { console.log('Kakashi è già attivo (fermalo con: stop kakashi).'); return false; }
  build();
  writeFileSync(log, '');
  const args = ['-g', '-a', app, '--stdout', log, '--stderr', log];
  const vars = {...Object.fromEntries(Object.entries(process.env).filter(([k]) => k.startsWith('KAKASHI_'))), ...extra};
  for (const [k, v] of Object.entries(vars)) args.push('--env', `${k}=${v}`);
  execFileSync('open', args);
  return true;
}
async function afterLaunch() {
  await new Promise(r => setTimeout(r, 1500));
  const pid = ownedPid();
  if (!pid) { console.error(`Non avviato. Log: ${log}\n` + readFileSync(log, 'utf8')); process.exitCode = 1; }
  else console.log(`Kakashi avviato (pid ${pid}).\n` + readFileSync(log, 'utf8').trim());
}

// ---- OBS: camera virtuale col video elaborato (scena pronta, avviata e fermata da qui) ----
const obsApp = '/Applications/OBS.app';
const obsDir = path.join(os.homedir(), 'Library', 'Application Support', 'obs-studio');
const obsPidFile = path.join(os.homedir(), '.local', 'state', 'kakashi-obs.pid');
const useObs = () => process.env.KAKASHI_OBS !== '0' && existsSync(obsApp);
const obsPid = () => { try { return Number(execFileSync('pgrep', ['-x', 'OBS'], {encoding: 'utf8'}).split('\n')[0]) || null; } catch { return null; } };
const ours = () => { try { const p = Number(readFileSync(obsPidFile, 'utf8')); return p && p === obsPid() ? p : null; } catch { return null; } };
const sleep = ms => new Promise(r => setTimeout(r, ms));

function writeObsConfig(windowId) {
  const profile = path.join(obsDir, 'basic', 'profiles', 'Kakashi');
  mkdirSync(profile, {recursive: true});
  mkdirSync(path.join(obsDir, 'basic', 'scenes'), {recursive: true});
  const globalIni = path.join(obsDir, 'global.ini');
  if (!existsSync(globalIni)) {   // prima volta: niente procedura guidata
    writeFileSync(globalIni, '[General]\nFirstRun=true\nConfirmOnExit=false\n\n[Basic]\nProfile=Kakashi\nProfileDir=Kakashi\nSceneCollection=Kakashi\nSceneCollectionFile=Kakashi\n');
  }
  writeFileSync(path.join(profile, 'basic.ini'),
    '[General]\nName=Kakashi\n\n[Video]\nBaseCX=1280\nBaseCY=720\nOutputCX=1280\nOutputCY=720\nFPSType=0\nFPSCommon=30\n\n[Output]\nMode=Simple\n');
  const win = {type: 1, window: windowId, window_name: 'Kakashi Video', owner_name: 'Kakashi', show_cursor: false, show_empty_names: true, show_hidden_windows: true};
  const scene = {
    current_scene: 'Kakashi', current_program_scene: 'Kakashi', name: 'Kakashi',
    scene_order: [{name: 'Kakashi'}],
    modules: {'scripts-tool': [{path: path.join(dir, 'obs-virtualcam.lua'), settings: {}}]},
    sources: [
      {id: 'screen_capture', versioned_id: 'screen_capture', name: 'Kakashi Video', settings: win, enabled: true, muted: false, volume: 1.0, flags: 0, mixers: 0, monitoring_type: 0, balance: 0.5, sync: 0, prev_ver: 0, 'push-to-mute': false, 'push-to-talk': false},
      {id: 'scene', versioned_id: 'scene', name: 'Kakashi', enabled: true, muted: false, volume: 1.0, flags: 0, mixers: 0, monitoring_type: 0, balance: 0.5, sync: 0, prev_ver: 0,
        settings: {id_counter: 1, items: [{name: 'Kakashi Video', visible: true, locked: false, align: 5, pos: {x: 0, y: 0}, scale: {x: 1, y: 1}, rot: 0, bounds_type: 2, bounds_align: 0, bounds: {x: 1280, y: 720}, crop_left: 0, crop_top: 0, crop_right: 0, crop_bottom: 0, id: 1, group_item_backup: false}]}},
    ],
  };
  writeFileSync(path.join(obsDir, 'basic', 'scenes', 'Kakashi.json'), JSON.stringify(scene, null, 2));
}
function quitOurObs() {
  const pid = ours(); if (!pid) return false;
  try { execFileSync('osascript', ['-e', 'tell application "OBS" to quit'], {stdio: 'ignore', timeout: 4000}); } catch { try { process.kill(pid, 'SIGTERM'); } catch {} }
  // se resta aperto (per esempio bloccato da un avviso di OBS) si chiude con forza e si toglie il segno di "chiusura anomala"
  for (let i = 0; i < 12 && obsPid() === pid; i++) execFileSync('sleep', ['0.5']);
  if (obsPid() === pid) {
    try { process.kill(pid, 'SIGKILL'); } catch {}
    try { execFileSync('rm', ['-rf', path.join(obsDir, '.sentinel')]); } catch {}
  }
  try { unlinkSync(obsPidFile); } catch {}
  return true;
}

// La camera virtuale è accesa quando OBS lo scrive nel suo log. --startvirtualcam può fallire in silenzio
// se parte prima che l'estensione sia pronta: in quel caso si riavvia OBS (al secondo giro è pronta).
const obsLogDir = path.join(obsDir, 'logs');
const newestObsLog = since => {   // solo log creati/aggiornati dopo "since": mai quello della sessione precedente
  try {
    const f = execFileSync('ls', ['-t', obsLogDir], {encoding: 'utf8'}).split('\n')[0];
    const full = path.join(obsLogDir, f);
    return statSync(full).birthtimeMs >= since ? readFileSync(full, 'utf8') : '';
  } catch { return ''; }
};
async function obsStarted(seconds, since) {   // OBS è partito davvero quando scrive il suo log
  for (let i = 0; i < seconds * 2; i++) { if (/Command Line Arguments/.test(newestObsLog(since))) return true; await sleep(500); }
  return false;
}
async function virtualCamOn(seconds, since) {
  for (let i = 0; i < seconds * 2; i++) { if (/Starting Virtual Camera output/.test(newestObsLog(since))) return true; await sleep(500); }
  return false;
}
function launchObs() {   // la camera virtuale la accende lo script obs-virtualcam.lua caricato dalla scena
  execFileSync('open', ['-g', '-j', '-a', obsApp, '--args', '--profile', 'Kakashi', '--collection', 'Kakashi', '--scene', 'Kakashi']);
}
const waitGone = async () => { for (let i = 0; i < 40 && obsPid(); i++) await sleep(250); };
async function startObs() {
  if (!useObs()) return;
  let id = null;
  for (let i = 0; i < 40 && !id; i++) {   // aspetta che Kakashi dica l'id della sua finestra video
    const m = readFileSync(log, 'utf8').match(/Finestra video: (\d+)/); if (m) id = Number(m[1]); else await sleep(250);
  }
  if (!id) { console.log('OBS: Kakashi non ha ancora aperto la finestra video (permesso camera in attesa?). Rilancia run kakashi dopo averlo consentito.'); return; }
  if (obsPid() && !ours()) { console.log('OBS è già aperto (non da me): chiudilo e rilancia run kakashi, oppure aggiungi tu la sorgente "Kakashi Video".'); return; }
  if (ours()) { quitOurObs(); for (let i = 0; i < 40 && obsPid(); i++) await sleep(250); }
  writeObsConfig(id);
  for (let tentativo = 1; tentativo <= 3; tentativo++) {
    const since = Date.now() - 1000;
    launchObs();
    for (let i = 0; i < 40 && !obsPid(); i++) await sleep(250);
    const pid = obsPid();
    if (!pid) { console.log('OBS non è partito.'); return; }
    mkdirSync(path.dirname(obsPidFile), {recursive: true}); writeFileSync(obsPidFile, String(pid));
    if (await obsStarted(12, since) && await virtualCamOn(40, since)) { console.log(`OBS avviato (pid ${pid}), camera virtuale accesa: in Discord/Meet scegli "OBS Virtual Camera".`); return; }
    if (tentativo < 3) { console.log('La camera virtuale non è partita, riavvio OBS…'); quitOurObs(); for (let i = 0; i < 40 && obsPid(); i++) await sleep(250); await sleep(3000); }
    else console.log('OBS è aperto ma la camera virtuale non risulta accesa: in OBS premi "Avvia camera virtuale".');
  }
}

const action = process.argv[2] || 'start';
if (action === 'stop') {
  const pid = ownedPid();
  if (quitOurObs()) console.log('OBS chiuso.');
  if (!pid) { console.log('Kakashi non è in esecuzione.'); process.exit(0); }
  process.kill(pid, 'SIGTERM');
  console.log('Kakashi fermato.');
} else if (action === 'status') {
  const pid = ownedPid(); console.log(pid ? `Kakashi attivo (pid ${pid}). Log: ${log}` : 'Kakashi fermo.');
} else if (action === 'log') {
  console.log(existsSync(log) ? readFileSync(log, 'utf8') : 'Nessun log.');
} else if (action === 'selftest') {
  build(); process.exitCode = spawnSync(bin, ['selftest'], {stdio: 'inherit'}).status ?? 1;
} else if (action === 'demo') {   // prova l'effetto fumo su fotogrammi finti, senza camera
  build(); const out = process.argv[3] || path.join(os.tmpdir(), 'kakashi-demo'); spawnSync(bin, ['demo', out], {stdio: 'inherit'});
} else if (action === 'start') {
  if (launch()) await afterLaunch();
  await startObs();   // anche se Kakashi era già attivo: riallinea OBS
} else if (action === 'debug') {   // stampa le misure a ogni fotogramma: serve per tarare le soglie
  if (launch({KAKASHI_DEBUG: 1})) await afterLaunch();
  await startObs(); console.log(`Misure in tempo reale:  tail -f ${log}`);
} else { console.error('Uso: node kakashi.mjs [start|stop|status|debug|selftest|demo|log]'); process.exitCode = 1; }
