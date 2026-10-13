# Privacy Helper

Applicazione locale React e Express per consultare una directory di data broker e registrare richieste di cancellazione in SQLite.

## Funzioni disponibili

- Elenco e gestione dei broker e dei loro collegamenti di opt-out.
- Creazione, consultazione e aggiornamento delle richieste registrate.
- API locale, crittografia dei campi risposta e metadata, backup SQLite.
- Esportazione JSON dei dati dalla pagina impostazioni.

La ricerca dei broker produce suggerimenti: non verifica se qualcuno possiede i tuoi dati. Le sezioni scansione privacy, monitoraggio email e automazione sono prototipi dimostrativi. Non inviano email o richieste di cancellazione reali. Una richiesta registrata va presentata manualmente dal sito del broker; aggiornane poi lo stato nell’app.

## Sviluppo locale

Richiede Node.js 22 e npm. Per backup e ripristino installa anche `sqlite3`.

```sh
npm ci --ignore-scripts
npm ci --prefix src/server
npm run build --prefix src/server
npm start --prefix src/server
```

In un secondo terminale:

```sh
npm run dev
```

Apri [localhost:8080](http://localhost:8080). Vite inoltra `/api` al backend su `127.0.0.1:3000`.

Per servire la build con il solo backend:

```sh
npm run build
npm start --prefix src/server
```

Apri [localhost:3000](http://localhost:3000). Il backend serve anche gli asset e le rotte del frontend.

`.env.example` documenta le opzioni. Vite legge `.env` per le variabili `VITE_*`; per Express esporta le variabili nel terminale o usa `node --env-file=.env src/server/dist/server/index.js` dalla cartella del progetto. I percorsi relativi sono risolti dalla directory di avvio.

## Docker

```sh
docker compose up --build -d
```

Apri [localhost:3000](http://localhost:3000). Il container esegue Node 22 con utente non privilegiato. Il volume persistente `open-broker-data` contiene database, chiavi, log e backup. Non eliminare il volume se vuoi conservare i dati.

## Verifiche

```sh
npm run build
npx tsc -p tsconfig.app.json --noEmit
npm run build --prefix src/server
python3 scripts/smoke-test.py
```

`GET /api/health` verifica backend e database. Il servizio ascolta soltanto su loopback per impostazione predefinita; non dispone di autenticazione multiutente.

## Dati e backup

Conserva database e chiave `.encryption_key` insieme in un backup sicuro. I backup del database non includono la chiave. I nomi effettivi dei backup restituiti da `GET /api/backups` si usano per il ripristino. La cancellazione dei dati svuota le tabelle e rimuove i backup locali senza interrompere la connessione SQLite.

Licenza [MIT](LICENSE).
