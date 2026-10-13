# Privacy Helper

Strumento della raccolta [**Tools**](../README.md), in precedenza **Open Broker Remover**. La versione corrente si trova in `andbardii/tools`, cartella `privacy-helper/`; la repository separata è conservata come archivio storico.

[![React](https://img.shields.io/badge/React-18-blue)](https://react.dev/)
[![License](https://img.shields.io/badge/License-MIT-green)](https://opensource.org/licenses/MIT)

Privacy Helper è un progetto open-source in continuo sviluppo, nato per essere uno strumento gratuito e accessibile a chiunque. L'obiettivo è consentire la rimozione dei dati personali dai data broker con gestione locale dei dati. I dati dell’applicazione sono gestiti localmente; le richieste ai data broker possono richiedere comunicazioni esterne.

### 🛠️ In fase di sviluppo
Il progetto è ancora in fase di sviluppo ed è nato dal desiderio di costruire qualcosa di utile nel tempo extra. Ogni contributo, suggerimento o richiesta è non solo ben accetto, ma incoraggiato! Apri una pull request o crea una issue per proporre modifiche, aggiungere funzionalità o segnalare bug.

## Stato della build

La verifica eseguita durante la migrazione ha rilevato import di pagine assenti nella versione originale, tra cui `src/pages/FindBrokers` e `src/pages/NewRequest`. `npm run build` attualmente non termina correttamente anche nel commit originale `e60bc70022`. I comandi sotto descrivono la configurazione del progetto; queste dipendenze mancanti devono essere ripristinate prima di ottenere una build utilizzabile. La migrazione e il cambio di nome non correggono questo problema preesistente.

## Indice
- [Funzionalità Principali](#funzionalita-principali)
- [Tecnologie Utilizzate](#tecnologie-utilizzate)
- [Sistema di Crittografia](#sistema-di-crittografia)
- [Sistema di Backup](#sistema-di-backup)
- [Esecuzione con Docker](#esecuzione-con-docker)
- [Sviluppo Locale](#sviluppo-locale)
- [Licenza](#licenza)

## Funzionalità Principali
- **Richiesta di Eliminazione Dati**: Gestisce automaticamente le richieste di cancellazione dei dati personali verso vari data broker.
- **Esecuzione in Locale**: Frontend, backend e database possono essere eseguiti sul proprio computer.
- **Gestione Efficiente**: Ottimizzazione dei processi per garantire velocità e affidabilità.
- **Compatibilità Multipiattaforma**: Supporta ambienti Windows, macOS e Linux tramite Docker.
- **Persistenza dei Dati**: Utilizza SQLite per salvare i dati in modo locale e sicuro.
- **Crittografia dei dati locali**: Protezione dei dati sensibili con crittografia AES-256-GCM e gestione sicura delle chiavi.

## Tecnologie Utilizzate
Il progetto è costruito utilizzando le seguenti tecnologie:
- **Frontend**:
- Vite
- TypeScript
- React
- Shadcn-UI
- Tailwind CSS
- **Backend**:
  - Node.js con Express
  - TypeScript
- Better-SQLite3 per la gestione locale del database
  - Crittografia AES-256-GCM per la protezione dei dati sensibili
- **Sicurezza**:
  - Helmet per le intestazioni HTTP di sicurezza
  - Content Security Policy per prevenire XSS
  - Rate limiting per prevenire attacchi di forza bruta
  - Container non-root per l'esecuzione Docker
- **Containerizzazione**:
  - Docker e Docker Compose per la distribuzione

## Sistema di Crittografia
L'applicazione include un sistema di crittografia completo per proteggere i dati sensibili memorizzati localmente:

### Caratteristiche della Crittografia
- **Standard di Cifratura**: AES-256-GCM per i dati gestiti dal sistema di crittografia
- **Gestione delle Chiavi**: Generazione sicura e storage isolato delle chiavi di crittografia
- **Validazione delle Chiavi**: Test automatico per garantire l'integrità delle chiavi
- **Persistenza Sicura**: Le chiavi vengono salvate in volumi Docker isolati con permessi restrittivi
- **Backup delle Chiavi**: Esportazione e importazione sicura delle chiavi per il backup

### Funzionamento della Crittografia
1. **Avvio Iniziale**: Al primo avvio, il sistema genera automaticamente una nuova chiave di crittografia
2. **Avvii Successivi**: Il sistema cerca la chiave esistente e la utilizza per decifrare i dati
3. **Controllo Integrità**: Viene eseguito un test di validazione per verificare che la chiave sia funzionante
4. **Crittografia Opt-in**: La crittografia può essere abilitata o disabilitata dall'utente

### API di Crittografia
L'applicazione fornisce endpoint API per la gestione della crittografia:
- `/api/encryption/status`: Verifica lo stato della crittografia
- `/api/encryption/enable`: Abilita o disabilita la crittografia
- `/api/encryption/export-key`: Esporta la chiave per il backup (protetta da rate limiting)
- `/api/encryption/import-key`: Importa una chiave precedentemente esportata

## Sistema di Backup
L'applicazione include un sistema di backup automatico per proteggere i dati del database:

### Caratteristiche del Backup
- **Backup Automatici**: Backup periodici configurabili del database SQLite
- **Gestione della Retention**: Pulizia automatica dei backup più vecchi
- **Backup Manuali**: Possibilità di creare backup on-demand tramite API
- **Ripristino Sicuro**: Sistema di ripristino con backup temporaneo di sicurezza
- **Monitoraggio**: Logging dettagliato di tutte le operazioni di backup

### Configurazione dei Backup
Il sistema di backup può essere configurato tramite variabili d'ambiente:
- `DB_BACKUP_ENABLED`: Abilita/disabilita i backup automatici (default: true)
- `DB_BACKUP_INTERVAL`: Intervallo tra i backup in secondi (default: 86400, 24 ore)
- `DB_BACKUP_RETENTION`: Giorni di conservazione dei backup (default: 7)
- `BACKUP_DIR`: Directory dove salvare i backup (default: ./backups)

### API di Backup
L'applicazione fornisce endpoint API per la gestione dei backup:
- `GET /api/backups`: Lista tutti i backup disponibili
- `POST /api/backups`: Crea un nuovo backup manualmente
- `POST /api/backups/restore/:filename`: Ripristina un backup specifico

### Gestione dei Backup con Docker
Quando si utilizza Docker, i backup vengono salvati nel volume `open-broker-data`:
```sh
# Visualizza i backup disponibili
curl http://localhost:3000/api/backups

# Crea un backup manuale
curl -X POST http://localhost:3000/api/backups

# Ripristina un backup specifico
curl -X POST http://localhost:3000/api/backups/restore/backup-2024-03-21T10-00-00.db
```

## Esecuzione con Docker
L'applicazione può essere facilmente eseguita utilizzando Docker, che incapsula sia il frontend che il backend in un unico container:

1. **Prerequisiti**:
   - Docker e Docker Compose installati sulla macchina

2. **Avvio dell'applicazione**:
   ```sh
   # Clona il repository
   git clone https://github.com/andbardii/tools.git
   cd tools/privacy-helper

   # Avvia l'applicazione con Docker Compose
   docker compose up -d --build
   ```

3. **Accesso all'applicazione**:
   - Apri un browser e naviga a `http://localhost:3000`

4. **Gestione dei dati**:
   I dati sono persistenti grazie al volume Docker `open-broker-data` che viene creato automaticamente. Questo garantisce che i dati non vengano persi tra i riavvii del container.

5. **Sicurezza e Monitoraggio del Container**:
   - L'applicazione viene eseguita come utente non-root per una maggiore sicurezza
   - La porta dell’applicazione è esposta sul computer host solo su localhost (127.0.0.1)
   - Le intestazioni di sicurezza HTTP sono configurate per prevenire attacchi comuni
   - Health check automatico ogni 30 secondi per monitorare lo stato dell'applicazione
   - Limiti di risorse configurati per garantire prestazioni stabili:
     - CPU: limite massimo 50%, minimo garantito 25%
     - Memoria: limite massimo 512MB, minimo garantito 256MB

6. **Ottimizzazioni Docker**:
   - Build multi-stage per ridurre la dimensione dell'immagine finale
   - Caching ottimizzato dei layer per build più veloci
   - Separazione chiara tra dipendenze di produzione e sviluppo
   - Gestione efficiente delle dipendenze con `npm ci`

7. **Monitoraggio dello Stato**:
   ```sh
   # Verifica lo stato del container e il health check
   docker ps
   
   # Visualizza informazioni dettagliate sullo stato dell'applicazione
   curl http://localhost:3000/api/health
   ```
   L'endpoint `/api/health` fornisce informazioni dettagliate su:
   - Stato generale dell'applicazione
   - Versione corrente
   - Stato del database
   - Stato della crittografia
   - Metriche di sistema (uptime, utilizzo memoria)

## Sviluppo Locale

I percorsi di seguito partono dalla directory che contiene il clone `tools/`, salvo dove indicato. Il backend usa la porta `3001`; il frontend viene avviato sulla porta `3000`, coerente con la configurazione CORS attuale.

### Setup del Frontend e del Backend separati
Per lo sviluppo, puoi eseguire il frontend e il backend separatamente:

1. **Setup del Backend**:
   ```sh
   cd tools/privacy-helper/src/server
   npm ci
   PORT=3001 npm run dev
   ```

2. **Setup del Frontend**:
   ```sh
   # In una nuova finestra di terminale, dalla radice di Tools
   cd privacy-helper
   npm ci
   VITE_API_URL=http://localhost:3001/api npm run dev -- --port 3000
   ```

3. **Variabili d'ambiente**:
   Per il frontend puoi impostare `VITE_API_URL` nel comando sopra oppure in `tools/privacy-helper/.env` con:
   ```
   VITE_API_URL=http://localhost:3001/api
   ```

### Modifica del Codice
Puoi modificare il codice seguendo il classico flusso di lavoro Git o lavorando in locale.

#### Metodo Classico: Fork, Clone e Pull Request
1. **Fork del Repository**: Clicca su "Fork" nella pagina GitHub di [andbardii/tools](https://github.com/andbardii/tools).
2. **Clonazione**:
   ```sh
   git clone https://github.com/<IL_TUO_USERNAME>/tools.git
   cd tools/privacy-helper
   ```
3. **Crea un Branch**:
   ```sh
   git checkout -b nome-del-branch
   ```
4. **Modifiche e Test**
5. **Commit e Push**:
   ```sh
   git add .
   git commit -m "Descrizione delle modifiche"
   git push origin nome-del-branch
   ```
6. **Pull Request**: Vai su GitHub e apri una pull request.

## Licenza
Questo progetto è distribuito sotto la licenza MIT.

## Compatibilità con il nome precedente

Per conservare l’accesso ai dati esistenti, il database mantiene il nome `open-broker-remover.db` e il volume Docker mantiene il nome `open-broker-data`. Il cambio di nome del progetto non migra né elimina questi dati.

La cronologia Git originale è conservata nel tag `migration/privacy-helper`: vedi [MIGRATION.md](../MIGRATION.md). La [licenza MIT](LICENSE) originale resta valida.
