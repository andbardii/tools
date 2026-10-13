# Migrazione in tools

Migrazione del 13 ottobre 2026. Importazioni tramite `git subtree add`, senza `--squash` e senza riscrivere la cronologia. Gli hash originali restano invariati.

| Progetto | Repository originale | Branch | Commit importato | Tag |
| --- | --- | --- | --- | --- |
| [privacy-helper](privacy-helper/) | [andbardii/privacy-helper](https://github.com/andbardii/privacy-helper) | `main` | `e60bc7002250fe620a8b89cc2c52a49ff2108fb8` | `migration/privacy-helper` |

## Consultare i commit originali

```sh
# Cronologia completa della raccolta e dei progetti importati
git log --all --graph --oneline

# Cronologia originale di un progetto, prima della migrazione
git log migration/privacy-helper

# Modifiche alla cartella dopo l’importazione
git log -- privacy-helper/
```

Prima dell’importazione i file erano nella radice delle singole repository: un filtro sul nuovo percorso non mostra da solo tutti i commit precedenti. Usa il tag di migrazione per consultarli con i percorsi originali.

Le repository sorgenti vengono conservate come archivi con un collegamento alla nuova posizione. Issue, pull request e release storiche rimangono nelle repository originali; non sono trasferite da un’importazione Git. Le licenze di ciascun progetto sono conservate.

`open-broker-remover` viene rinominato in `privacy-helper` prima dell’archiviazione. I nomi di database e volume Docker (`open-broker-remover.db`, `open-broker-data`) restano invariati per mantenere l’accesso ai dati già esistenti.
