# Screenshot Page

Parte della raccolta [Tools](../README.md). Script Node.js con Puppeteer per salvare uno screenshot a tutta altezza in `screenshot.png`.

Dalla radice di Tools:

```sh
cd screenshot-page
npm ci
node screenshots.js
```

Prima dell’esecuzione, imposta l’URL in `page.goto(...)` e, se necessario, le dimensioni in `screenshots.js`. Il file generato viene scritto nella cartella corrente. L’installazione di Puppeteer può scaricare un browser.
