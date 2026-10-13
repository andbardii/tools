# Sitemap Generator

Parte della raccolta [Tools](../README.md). Genera una sitemap XML con la libreria Node.js `sitemap`.

Prima dell’esecuzione, modifica `sitemapgenerator.js`: imposta `hostname`, completa l’elenco `links` e scegli il percorso di output in `createWriteStream(...)`. La directory di destinazione deve esistere.

Dalla radice di Tools:

```sh
cd sitemap-generator
npm ci
node sitemapgenerator.js
```

Lo script scrive la sitemap nel percorso configurato e ne stampa il contenuto nel terminale.
