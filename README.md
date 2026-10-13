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

La cronologia originale di `tools` è conservata. Privacy Helper è stato importato da `open-broker-remover` senza squash, mantenendo i commit originali. Vedi [Provenienza e cronologia](#provenienza-e-cronologia) in questo README.

I contenuti originali di Tools mantengono la [licenza MIT](LICENSE). Privacy Helper conserva anche la [propria licenza](privacy-helper/LICENSE) e le relative attribuzioni.

## Provenienza e cronologia

Migrazione del 13 ottobre 2026. Importazioni tramite `git subtree add`, senza `--squash` e senza riscrivere la cronologia. Gli hash originali restano invariati.

| Progetto | Repository originale | Branch | Commit importato | Tag |
| --- | --- | --- | --- | --- |
| [privacy-helper](privacy-helper/) | `andbardii/privacy-helper` | `main` | `e60bc7002250fe620a8b89cc2c52a49ff2108fb8` | `migration/privacy-helper` |

### Consultare i commit originali

```sh
# Cronologia completa della raccolta e dei progetti importati
git log --all --graph --oneline

# Cronologia originale di un progetto, prima della migrazione
git log migration/privacy-helper

# Modifiche alla cartella dopo l’importazione
git log -- privacy-helper/
```

Prima dell’importazione i file erano nella radice delle singole repository: un filtro sul nuovo percorso non mostra da solo tutti i commit precedenti. Usa il tag di migrazione per consultarli con i percorsi originali.

Questa raccolta è la posizione corrente dei progetti importati. Un’importazione Git conserva commit e file, ma non trasferisce issue, pull request e release su GitHub. Le licenze di ciascun progetto sono conservate.

Il progetto `open-broker-remover` è stato rinominato in `privacy-helper` e integrato nella raccolta. La versione corrente è mantenuta in questa raccolta. I nomi di database e volume Docker (`open-broker-remover.db`, `open-broker-data`) restano invariati per mantenere l’accesso ai dati già esistenti.
