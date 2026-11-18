# Kakashi

Guarda la webcam e ha tre segnali: uno ti fa sparire dalla call con uno **sbuffo ninja**, uno ti trasforma in un **Real Stoner**, uno ti fa **zoomare sulla faccia** come nel momento «eh?» dei cartoni. In più, **le due mani a «C» vicino agli occhi** ti trasformano nello sviluppatore, e **ogni volta che bevi** (pugno che si avvicina alla bocca) il caffè viene contato in alto a destra. Ogni effetto ha il suo suono.

**Gesto:** parti con i **due pugni chiusi al centro** dell'inquadratura (fermi per mezzo secondo) e poi **apri le due mani insieme**. All'apertura:

1. una nuvola di fumo ti copre nel video;
2. sotto il fumo vieni sostituito dallo sfondo: nel video sparisci davvero. Per riempire il buco usa, in ordine, lo sfondo che ha imparato mentre lavori, poi una copia nitida del muro accanto a te (a sinistra e a destra), e solo in ultimo una sfocatura; il bordo è molto sfumato;
3. dopo ~2 secondi Kakashi ti butta fuori dalla call: chiude la scheda di Meet, Discord, Zoom, Teams, Whereby, Jitsi, Webex (Chrome, Brave, Edge, Arc, Vivaldi, Opera, Safari) oppure l'app nativa (Zoom, Discord, Teams, FaceTime). Le altre schede non si toccano.

## Secondo segnale: Real Stoner

**Gesto:** porta **due dita alla bocca** (indice e medio uniti, le altre chiuse, come per fumare): le punte devono stare **vicino alla bocca** (entro circa una larghezza di bocca), non in un punto qualsiasi dello schermo. Tienile mezzo secondo. Per circa 4 secondi:

1. l'immagine **si blocca**;
2. si **ingrigisce piano**, con una leggera vignettatura;
3. ti cadono sul naso gli **occhiali pixel stile Thug Life**;
4. ti spunta in bocca un **joint lunghissimo**, che esce dal lato in cui hai la mano (a destra o a sinistra della bocca), con la brace che pulsa e il fumo che sale, e a un certo punto una **sbuffata** dalla bocca;
5. in basso compare la scritta **REAL STONER** (Impact inclinato, verde-giallo con contorno nero);
6. dissolvenza e torni al video dal vivo. Non ti butta fuori dalla call.

Se la mano davanti alla faccia fa perdere il volto per un attimo, usa l'ultimo visto. Tarature: `KAKASHI_SMOKE_HOLD` (secondi, default 0.5) e `KAKASHI_SMOKE_DIST` (distanza massima dita-bocca in larghezze di bocca, default 0.9: più basso = più vicino).

## Terzo segnale: zoom sulla faccia ("eh?")

**Gesto:** abbassa un po' un sopracciglio (o tutti e due, o uno più dell'altro) e **storci un po' la testa** da un lato o dall'altro, come quando qualcosa non ti torna. Se guardi in su, in giù o di lato (un angolo) **non** scatta: Kakashi controlla che la posa della testa sia quella di riposo (`KAKASHI_POSE_TOL`, default 10%). Non serve essere precisi: Kakashi impara da solo come sei a riposo (mediana degli ultimi 30 secondi di altezza dei sopraccigli e inclinazione della testa, sempre aggiornata, quindi si riallinea da sola) e scatta quando te ne discosti per mezzo secondo. Subito dopo l'avvio ha bisogno di un paio di secondi per imparare. Ogni segnale scatta **una volta** e si riarma solo dopo quasi un secondo di riposo: se per un errore l'espressione risultasse "sempre attiva", non ripete in loop.

L'inquadratura fa una **spinta veloce sul volto** (con un piccolo rimbalzo) e subito dopo torna indietro, in circa 0,7 secondi, la stessa durata del suono, con una leggera vignettatura. Zoom di default 2,5×. Se ti muovi, segue il volto. Tarature: `KAKASHI_BROW` (sopracciglio abbassato sotto questa frazione di quello a riposo, default 0.88), `KAKASHI_TILT` (gradi di testa storta, default 5), `KAKASHI_BROW_HOLD` (secondi, default 0.35), `KAKASHI_ZOOM` (ingrandimento, default 2.5). `run kakashi debug` mostra le misure.

## Quarto segnale: gli occhiali → ti trasformi nello sviluppatore

**Gesto:** porta **entrambe le mani a «C» vicino agli occhi**, una per lato (come quando ti metti gli occhiali con due mani), e tienile mezzo secondo. Come per il Real Stoner non si cerca di riconoscere l'oggetto: conta il **movimento giusto**. Le mani devono stare entrambe vicino agli occhi, una a sinistra e una a destra. Dopo uno scatto si riarma solo dopo quasi un secondo con le mani giù.

**Effetto (4,6 s):** l'immagine **resta viva** (non si ferma) e si trasforma:
1. un **lampo** e un'**onda d'urto** che parte dalla tua faccia, un breve **glitch** con i colori separati;
2. una **linea di scansione** scende dall'alto e rivela il look da sviluppatore: toni **ciano e magenta**, più contrasto e vignettatura, con una **pioggia di codice** discreta;
3. attorno alla tua faccia appare un **mirino olografico** (angoli, anello che gira) con l'etichetta `build developer.exe` e una **barra di caricamento** che si riempie;
4. due **finestre da editor** scivolano ai lati: un file TypeScript con il codice colorato (`const tu = new Sviluppatore(); tu.caffe += 1;`…) e un `git log` (`fix: fix del fix`, `wip: non toccare il main`);
5. il **terminale in una finestra** digita `$ sudo become developer` … `> benvenuto, sviluppatore`;
6. il titolo **DEVELOPER** al neon (ciano→magenta) esplode in alto con le **scintille** e il sottotitolo `mode: ON · funziona sulla mia macchina`;
7. dissolvenza e torni al video normale.

## Contatore dei caffè

**Gesto:** quando bevi, porta un **pugno** (con l'indice anche un po' disteso, o no) **vicino alla bocca avvicinando la mano**. Kakashi riconosce il movimento: un pugno **sotto la linea degli occhi** (fronte e capelli non contano) che si **avvicina alla bocca** (o che arriva vicino alla bocca dopo che prima non c'era) e ci resta almeno 0,35 secondi. Il riconoscimento tiene tutto il sorso anche se la distanza oscilla o la mano sparisce per un attimo; un solo scatto per sorso. Una mano ferma vicino alla bocca da sempre (per esempio mentre pensi) **non** conta, e nemmeno una mano aperta.

Per 3,4 secondi compare in alto a destra, **nel video della call**, una pillola «☕ Caffè bevuto! · n. 3» che entra da destra, resta ed esce: **compare solo a ogni nuovo caffè**, non resta sempre in vista. Il conteggio (azzerato a mezzanotte) è salvato in `~/.local/state/kakashi-coffee.json` e sopravvive ai riavvii. Al massimo un caffè ogni 8 secondi (un sorso solo). Il numero compare per qualche secondo anche nella finestrella. Taratura: `KAKASHI_DRINK` (quanto vicino alla bocca, in dimensioni di viso, default 1.0; bevendo il pugno sta a 0,45-0,8). `run kakashi debug` stampa a ogni fotogramma la distanza del pugno dalla bocca, da quanto tempo è vicino e se ha riconosciuto l'avvicinamento.

Limite: non guarda cosa c'è nella mano, quindi non distingue una tazza opaca da un bicchiere d'acqua: ogni "pugno alla bocca" conta come un caffè.

## Suoni

Ogni effetto ha il suo suono, sintetizzato dal programma (nessun file audio) e suonato sull'uscita audio del Mac: un bip quando i pugni sono pronti; soffio, tonfo e "puf" con la sparizione e il "pop" di uscita per lo sbuffo; un solo giro del ritmo "ta-ga-ta-ga-da" con basso, cassa e charleston, i rimbalzi degli occhiali, lo sfrigolio della brace e la sbuffata per il Real Stoner; solo il "vwoop" d'ingresso per lo zoom; sweep, glitch, tastiera che digita e un accordo potente per la trasformazione in sviluppatore; due sorsi e un campanello per il caffè. Lo sbuffo ninja non ha più il bip iniziale. `KAKASHI_SOUND=0` li spegne. Attenzione: li sentono solo le tue casse o cuffie, **non la call** (la call riceve solo il video).

Una finestrella (specchio della camera, con le mani tracciate) sta sempre sopra tutto, anche alle app a schermo intero, e non intralcia i click: diventa gialla mentre i pugni si "armano", rossa quando sei pronto ad aprire.

## Uso

```sh
node kakashi.mjs start     # avvia (compila al primo avvio)
node kakashi.mjs stop
node kakashi.mjs status
node kakashi.mjs debug     # stampa le misure a ogni fotogramma, per tarare il gesto
node kakashi.mjs selftest  # prova la logica del gesto, senza camera
node kakashi.mjs demo      # scrive i fotogrammi degli effetti (fumo e Real Stoner) su una scena finta, senza camera; con KAKASHI_SCENE=stanza una scena più realistica
node kakashi.mjs log
```

Dal terminale: `run kakashi`, `stop kakashi` (e `run kakashi debug|status|log|demo`).
Per provare senza chiudere davvero niente: `KAKASHI_DRY=1 run kakashi` (nel log scrive cosa chiuderebbe).

## Mandare il video con il fumo nella call (OBS)

Meet e gli altri vedono una camera, non Kakashi: il video elaborato esce in una finestra, **"Kakashi Video"**, che OBS cattura e rimanda come camera virtuale. Una volta sola:

1. Avvia Kakashi (`run kakashi`): compare la finestra "Kakashi Video" (sta dietro a tutte le altre finestre, a livello scrivania, e non intralcia: non chiuderla. Con `KAKASHI_VIDEO=show` la porti davanti per vederla).
2. In OBS: **Sorgenti → + → Cattura schermo macOS**, metodo **Cattura finestra**, finestra **Kakashi: Kakashi Video**. Adatta la sorgente alla tela.
3. In OBS: **Avvia camera virtuale**.
4. In Meet/Discord/Zoom scegli come camera **OBS Virtual Camera**.

Se non usi OBS, `KAKASHI_VIDEO=0` nasconde la finestra.

## Permessi (primo avvio)

App `~/Applications/Kakashi.app`. Consenti **Fotocamera** quando richiesto e, al primo scatto, **Automazione** (per chiudere le schede del browser). OBS ha bisogno del permesso **Registrazione schermo** per catturare la finestra. Ogni ricompilazione di Kakashi cambia la firma e può far richiedere di nuovo i permessi. La camera resta usabile da altre app nello stesso momento.

## Taratura (variabili d'ambiente)

| Variabile | Default | Cosa fa |
|---|---|---|
| `KAKASHI_FIST_MAX` | 1.45 | quanto devono essere chiuse le dita per contare come pugno (più basso = più rigido) |
| `KAKASHI_OPEN_MIN` | 1.6 | quanto devono essere aperte per contare come mano aperta (più alto = più rigido) |
| `KAKASHI_FIST_HOLD` | 0.4 | secondi di pugni fermi per armarsi |
| `KAKASHI_WINDOW` | 1.2 | secondi concessi per aprire le mani dopo l'ultimo pugno |
| `KAKASHI_CENTER` | 0.2 | scostamento massimo dal centro (frazione di larghezza) |
| `KAKASHI_APART` | 3.5 | distanza massima tra i polsi a pugni chiusi, in larghezze di palmo |
| `KAKASHI_COOLDOWN` | 8 | pausa in secondi dopo uno scatto |
| `KAKASHI_SOUND` | 1 | `0` = niente suoni |
| `KAKASHI_FLIP_TEXT` | 0 | `1` = scritte rovesciate nel video: nella tua anteprima di Meet/Discord (che l'app specchia) si leggono dritte, ma **agli altri arrivano al contrario** |
| `KAKASHI_POSE_TOL` | 0.10 | quanto può cambiare la posa della testa prima che lo zoom non scatti |
| `KAKASHI_DRINK` | 0.7 | quanto vicino alla bocca deve arrivare il pugno per contare un caffè (dimensioni di viso) |
| `KAKASHI_FX` | 1 | `0` = niente fumo: ti disconnette subito |
| `KAKASHI_DRY` | | `1` = non chiude niente, scrive nel log cosa chiuderebbe |
| `KAKASHI_POS` | `br` | angolo della finestrella: `tl` `tr` `bl` `br` |
| `KAKASHI_CAMERA` | | parte del nome della camera da usare (di default: iPhone/Continuity, poi esterna, poi integrata) |
| `KAKASHI_VIDEO` | 1 | `0` = non mostra la finestra "Kakashi Video" |

Altre call: `~/.config/kakashi.json` con `{"urls": ["regex sull'URL"], "apps": ["bundle.id.app"]}`.

## Limiti

- Lo sfondo con cui ti sostituisce lo impara mentre lavori: più ti sposti, meglio impara cosa c'è dietro di te. Per i punti che non ha mai visto copia il muro accanto a te, quindi un oggetto dietro di te può riapparire "duplicato" o tagliato a metà.
- Se la luce o la camera cambiano molto, lo sfondo appreso può non combaciare del tutto.
- Le app native (Discord, Zoom, Teams, FaceTime) vengono chiuse del tutto se sono aperte, anche se in quel momento non sei in call.
- Firefox non permette di chiudere le schede da fuori: non è gestito.
- L'audio non viene toccato: a uscire dalla call ci pensa la chiusura della scheda.

## Requisiti

macOS con Xcode Command Line Tools (`swiftc`) e Node.js; OBS per mandare il video nella call.
