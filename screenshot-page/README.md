# Screenshot Page

Cattura pagine web da terminale con Puppeteer, a tutta altezza o limitate al viewport. Mantiene le dimensioni del viewport durante il caricamento, così il layout responsive non viene alterato dall’altezza della pagina.

## Installazione

Richiede Node.js 22.12 o successivo. Dalla cartella del tool:

```sh
npm ci
```

Puppeteer scarica il browser compatibile durante l’installazione. Per usare un browser già installato puoi impostare `PUPPETEER_EXECUTABLE_PATH` al suo eseguibile.

## Utilizzo

```sh
npm start -- https://example.com --output screenshots/home.png
node screenshots.js https://example.com --width 390 --height 844 --viewport-only
node screenshots.js https://example.com --scroll --selector main --delay 1000
node screenshots.js --help
```

Il percorso di output è relativo alla directory corrente; le cartelle mancanti vengono create. Sono supportati PNG, JPEG e WebP. L’immagine predefinita è `screenshot.png`, con viewport 1440 × 900 e timeout di 30 secondi.

Il tool attende il caricamento della pagina. Per app che renderizzano contenuti in seguito, usa `--selector` per attendere un elemento visibile e `--delay` per un’ulteriore attesa in millisecondi. `--timeout` controlla i timeout delle operazioni del browser, fino a 300000 ms.

`--scroll` attiva contenuti caricati durante lo scorrimento, tornando poi in cima. Lo scorrimento è limitato a 100 passi: pagine infinite, animazioni e contenuti che richiedono interazioni possono necessitare di un’attesa o di uno script dedicato. Non vengono gestiti login o consenso cookie automaticamente. Errori di navigazione, risposte HTTP 4xx/5xx e percorsi non scrivibili terminano con codice 1; il browser viene chiuso anche in caso di errore.

## Verifica

```sh
npm test
```

I test usano un server locale: verificano dimensioni delle immagini, contenuti lazy, cattura del viewport, validazione CLI, errori HTTP, attesa di selettori e percorsi non validi. Non contattano siti esterni.

Documentazione: [ScreenshotOptions](https://pptr.dev/api/puppeteer.screenshotoptions), [Page.goto](https://pptr.dev/api/puppeteer.page.goto).
