#!/usr/bin/env node
import {spawn,execFileSync} from 'node:child_process';
import {openSync,readFileSync,writeFileSync,unlinkSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import os from 'node:os';
import path from 'node:path';
const dir=fileURLToPath(new URL('.',import.meta.url)),server=path.join(dir,'server.mjs');
const port=Number(process.env.ART_PORT||4322);
if(!Number.isInteger(port)||port<1024||port>65535)throw Error('ART_PORT deve essere tra 1024 e 65535.');
const pidfile=path.join(os.tmpdir(),`art-${process.getuid()}-${port}.pid`),log=path.join(os.tmpdir(),`art-${process.getuid()}-${port}.log`),url=`http://127.0.0.1:${port}`;
function ownedPid(){try{const pid=Number(readFileSync(pidfile,'utf8'));if(!Number.isInteger(pid)||pid<=1)return null;const command=execFileSync('ps',['-p',String(pid),'-o','command='],{encoding:'utf8'}).trim();return command.includes(server)?pid:null;}catch{return null;}}
async function healthy(){try{const r=await fetch(url+'/health',{signal:AbortSignal.timeout(500)});return r.ok&&(await r.json()).app==='art';}catch{return false;}}
function browser(){const child=spawn('open',[url],{stdio:'ignore'});child.on('error',()=>console.log(`Apri ${url}`));child.unref();}
const action=process.argv[2]||'start';
if(action==='stop'){
 const pid=ownedPid();if(!pid){console.log('Art non è in esecuzione.');process.exit(0);}process.kill(pid,'SIGTERM');try{unlinkSync(pidfile);}catch{}console.log('Art fermato.');
}else if(action==='start'){
 if(ownedPid()&&await healthy()){console.log(`Art è già aperto: ${url}`);browser();}
 else{
 const fd=openSync(log,'a'),child=spawn(process.execPath,[server],{cwd:dir,env:{...process.env,ART_PORT:String(port)},detached:true,stdio:['ignore',fd,fd]});
 child.on('error',e=>console.error(e.message));child.unref();
 let ready=false;for(let n=0;n<40;n++){await new Promise(r=>setTimeout(r,100));if(child.exitCode!==null)break;if(await healthy()){try{process.kill(child.pid,0);const command=execFileSync('ps',['-p',String(child.pid),'-o','command='],{encoding:'utf8'});if(command.includes(server)){ready=true;break;}}catch{break;}}}
 if(!ready){console.error(`Art non avviato: porta ${port} occupata o errore. Log: ${log}`);process.exitCode=1;}
 else{writeFileSync(pidfile,String(child.pid));console.log(`Art avviato: ${url}`);browser();}
 }
}else if(action==='status'){const pid=ownedPid();console.log(pid?`Art attivo (pid ${pid}): ${url}`:'Art fermo.');
}else{console.error('Uso: node art.mjs [start|stop|status]');process.exitCode=1;}
