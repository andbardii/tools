const $ = id => document.getElementById(id);
const formats = {square:[1080,1080], story:[1080,1920], portrait:[1080,1350]};
const state = {format:'square',wall:'brick',art:null,custom:null,size:79,shadow:55,brightness:100,x:.5,y:.5,name:'quadro'};
const brick = new Image(); brick.src='brick.png'; brick.onload=render; brick.onerror=()=>message('Impossibile caricare la parete: scegli lo sfondo bianco o ricarica la pagina.');
let pending = false;
function message(text){$('status').textContent=text;}
function geometry(w,h){
  if(!state.art)return null;
  const scale=Math.min(w*state.size/100/state.art.naturalWidth,h*state.size/100/state.art.naturalHeight);
  const aw=state.art.naturalWidth*scale,ah=state.art.naturalHeight*scale;
  return {x:Math.round(state.x*w-aw/2),y:Math.round(state.y*h-ah/2),w:Math.round(aw),h:Math.round(ah)};
}
function contain(){const [w,h]=formats[state.format],g=geometry(w,h);if(!g)return;state.x=Math.max(g.w/2/w,Math.min(1-g.w/2/w,state.x));state.y=Math.max(g.h/2/h,Math.min(1-g.h/2/h,state.y));}
function draw(canvas,w,h){
  canvas.width=w;canvas.height=h;
  const ctx=canvas.getContext('2d');ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality='high';ctx.fillStyle='#fff';ctx.fillRect(0,0,w,h);
  const bg=state.wall==='brick'?brick:state.wall==='custom'?state.custom:null;
  if(bg?.naturalWidth){const scale=Math.max(w/bg.naturalWidth,h/bg.naturalHeight);ctx.drawImage(bg,(w-bg.naturalWidth*scale)/2,(h-bg.naturalHeight*scale)/2,bg.naturalWidth*scale,bg.naturalHeight*scale);}
  const g=geometry(w,h);if(!g)return;
  const s=state.shadow/100;
  if(s){
    // A leftward cast shadow, with a dense area near the artwork and a long
    // soft falloff. Its top and bottom sit just inside the artwork's edges.
    const reach=Math.max(1,Math.round(g.w*.22));
    const shadow=document.createElement('canvas');
    shadow.width=reach+1;shadow.height=g.h;
    const sc=shadow.getContext('2d');
    const horizontal=sc.createLinearGradient(0,0,reach,0);
    for(const [position,alpha] of [[0,0],[.15,.015],[.43,.12],[.65,.52],[.82,.94],[1,1]]){
      horizontal.addColorStop(position,`rgba(22,24,26,${alpha*s*.60})`);
    }
    sc.fillStyle=horizontal;sc.fillRect(0,0,shadow.width,shadow.height);
    const vertical=sc.createLinearGradient(0,0,0,g.h);
    vertical.addColorStop(0,'transparent');
    vertical.addColorStop(.012,'rgba(0,0,0,.08)');
    vertical.addColorStop(.035,'black');
    vertical.addColorStop(.975,'black');
    vertical.addColorStop(1,'transparent');
    sc.globalCompositeOperation='destination-in';
    sc.fillStyle=vertical;sc.fillRect(0,0,shadow.width,shadow.height);
    ctx.drawImage(shadow,g.x-reach,g.y);
    shadow.width=shadow.height=1;
  }
  // Filtering is scoped to the artwork, leaving the wall and shadow unchanged.
  ctx.save();
  ctx.filter=`brightness(${state.brightness}%)`;
  ctx.drawImage(state.art,g.x,g.y,g.w,g.h);
  ctx.restore();
}
function render(){
  const [w,h]=formats[state.format];const previewWidth=Math.min(1080,Math.round(($('stage').clientWidth||600)*Math.min(devicePixelRatio||1,2)));
  $('stage').style.aspectRatio=`${w}/${h}`;
  $('stage').style.width=`min(100%, calc((100vh - 225px) * ${w/h}))`;
  draw($('preview'),previewWidth,Math.round(previewWidth*h/w));
  const factor=Number($('resolution').value),outW=w*factor,outH=h*factor;
  $('dimensions').textContent=`${w} × ${h}`;
  $('exportInfo').textContent=`PNG senza perdita · ${outW} × ${outH} px`;
  $('brightnessValue').textContent=state.brightness+'%';
  $('sizeValue').textContent=state.size+'%';$('shadowValue').textContent=state.shadow+'%';
  const g=geometry(outW,outH);
  $('quality').textContent=g&&(g.w>state.art.naturalWidth*1.05||g.h>state.art.naturalHeight*1.05)?'A questa dimensione il quadro verrà ingrandito: per più dettaglio usa una foto più grande o riduci la qualità di esportazione.':'';
  $('download').disabled=!state.art||pending;
}
async function loadFile(file){
  if(!file) return null;
  const url=URL.createObjectURL(file),img=new Image();
  try{img.src=url;await img.decode();return img;}finally{URL.revokeObjectURL(url);}
}
let artLoad=0,bgLoad=0;
$('artwork').addEventListener('change',async event=>{const request=++artLoad,file=event.target.files[0];if(!file)return;try{const img=await loadFile(file);if(request!==artLoad)return;state.art=img;state.name=file.name.replace(/\.[^.]+$/,'');state.x=state.y=.5;$('empty').hidden=true;$('imageInfo').textContent=`${file.name} · ${img.naturalWidth} × ${img.naturalHeight} px`;message('Quadro caricato. Trascinalo per sistemarlo sulla parete.');render();}catch{message('Formato non leggibile. Usa JPG, PNG o WebP; per HEIC esporta prima una copia JPG.');}event.target.value='';});
function selectWall(wall){state.wall=wall;document.querySelectorAll('[data-wall]').forEach(b=>{const active=b.dataset.wall===wall;b.classList.toggle('selected',active);b.setAttribute('aria-pressed',active);});document.querySelector('.custom').classList.toggle('active',wall==='custom');render();}
$('background').addEventListener('change',async event=>{const request=++bgLoad;try{const img=await loadFile(event.target.files[0]);if(!img||request!==bgLoad)return;state.custom=img;selectWall('custom');message('Sfondo personalizzato caricato. Viene adattato al formato riempiendo la composizione.');}catch{message('Sfondo non leggibile. Usa JPG, PNG o WebP.');}event.target.value='';});
document.querySelectorAll('[data-wall]').forEach(b=>b.onclick=()=>selectWall(b.dataset.wall));
document.querySelectorAll('[data-format]').forEach(b=>b.onclick=()=>{state.format=b.dataset.format;document.querySelectorAll('[data-format]').forEach(v=>{const active=v===b;v.classList.toggle('selected',active);v.setAttribute('aria-pressed',active);});contain();render();});
for(const key of ['size','shadow','brightness'])$(key).oninput=()=>{state[key]=Number($(key).value);contain();render();};
$('resetBrightness').onclick=()=>{state.brightness=100;$('brightness').value=100;render();};
$('center').onclick=()=>{state.x=state.y=.5;render();};$('resolution').onchange=render;
let drag=null;
$('preview').onpointerdown=e=>{if(!state.art)return;const rect=e.currentTarget.getBoundingClientRect(),g=geometry(rect.width,rect.height),x=e.clientX-rect.left,y=e.clientY-rect.top;if(x<g.x||x>g.x+g.w||y<g.y||y>g.y+g.h)return;drag={x:e.clientX,y:e.clientY,sx:state.x,sy:state.y};e.currentTarget.setPointerCapture(e.pointerId);};
$('preview').onpointermove=e=>{if(!drag)return;const r=e.currentTarget.getBoundingClientRect();state.x=drag.sx+(e.clientX-drag.x)/r.width;state.y=drag.sy+(e.clientY-drag.y)/r.height;contain();render();};
$('preview').onpointerup=$('preview').onpointercancel=()=>drag=null;
$('preview').onkeydown=e=>{if(!state.art||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key))return;e.preventDefault();const step=e.shiftKey?.01:.001;if(e.key==='ArrowLeft')state.x-=step;if(e.key==='ArrowRight')state.x+=step;if(e.key==='ArrowUp')state.y-=step;if(e.key==='ArrowDown')state.y+=step;contain();render();};
$('download').onclick=async()=>{if(!state.art||pending)return;pending=true;render();$('download').textContent='Esportazione…';try{if(state.wall==='brick')await brick.decode();const canvas=document.createElement('canvas'),[w,h]=formats[state.format],factor=Number($('resolution').value);draw(canvas,w*factor,h*factor);const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));if(!blob)throw Error('PNG non generato');const url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=`${state.name}-${state.format}-${w*factor}x${h*factor}.png`;link.click();setTimeout(()=>URL.revokeObjectURL(url),60000);canvas.width=canvas.height=1;message('PNG esportato alla risoluzione selezionata.');}catch{message('Esportazione non riuscita. Prova una risoluzione inferiore o ricarica lo sfondo.');}finally{pending=false;$('download').textContent='Esporta PNG';render();}};
let resize;window.addEventListener('resize',()=>{clearTimeout(resize);resize=setTimeout(render,100);});render();
