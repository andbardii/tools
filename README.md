# Tools

Raccolta personale di strumenti e script per privacy, automazione web e gestione di macOS. Ogni cartella è indipendente e mantiene le proprie dipendenze.

## Strumenti

| Cartella | Funzione | Tecnologie |
| --- | --- | --- |
| [privacy-helper](privacy-helper/) | Gestione locale delle richieste di rimozione dei dati personali dai data broker; in precedenza Open Broker Remover. | React, TypeScript, Node.js, SQLite, Docker |
| [screenshot-page](screenshot-page/) | Screenshot di pagine web a tutta altezza. | Node.js, Puppeteer |
| [sitemap-generator](sitemap-generator/) | Generazione di sitemap XML a partire da una lista di URL. | Node.js, sitemap |
| [macbook-generics](macbook-generics/) | Script personali di configurazione e manutenzione di macOS. | Zsh |

## Utilizzo

```sh
git clone https://github.com/andbardii/tools.git
cd tools
```

Consulta il README dello strumento scelto. Non è prevista un’installazione unica per tutta la raccolta.

## Cronologia e licenze

La cronologia originale di `tools` è conservata. Privacy Helper è stato importato da `open-broker-remover` senza squash, mantenendo i commit originali. Vedi [MIGRATION.md](MIGRATION.md).

I contenuti originali di Tools mantengono la [licenza MIT](LICENSE). Privacy Helper conserva anche la [propria licenza](privacy-helper/LICENSE) e le relative attribuzioni.
