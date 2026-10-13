# Sitemap Generator

Genera una sitemap XML da un elenco esplicito di URL. Utile per siti statici o per esportare le route pubbliche di un'applicazione. Non effettua scansioni del sito: includi nel JSON tutte le pagine che vuoi pubblicare nella sitemap.

## Requisiti e utilizzo

Node.js 20 o successivo e npm. Da questa directory:

```sh
npm ci
node sitemapgenerator.js --hostname https://example.com --input urls.json --output public/sitemap.xml
```

`--hostname` e `--input` sono obbligatori. `--output` è facoltativo: il valore predefinito è `sitemap.xml`. I percorsi dei file sono relativi alla directory da cui esegui il comando. Le directory di destinazione vengono create automaticamente; un file esistente viene sovrascritto. Usa `--help` per visualizzare la sintassi.

Crea un file `urls.json`, ad esempio:

```json
[
  "/",
  "/contatti",
  {
    "url": "/articoli/esempio",
    "lastmod": "2026-10-13",
    "changefreq": "monthly",
    "priority": 0.7
  }
]
```

Sono accettati percorsi relativi e URL assoluti appartenenti alla stessa origine di `--hostname` (protocollo, dominio e porta). L'hostname deve essere un'origine HTTP/HTTPS senza percorso, query, frammenti o credenziali. I frammenti degli URL vengono rimossi, gli URL duplicati normalizzati vengono inclusi una sola volta e i caratteri speciali vengono codificati per XML.

I metadati sono facoltativi: `lastmod` indica una data ISO, `priority` un numero tra 0 e 1 e `changefreq` uno dei valori `always`, `hourly`, `daily`, `weekly`, `monthly`, `yearly`, `never`. Inserisci solo informazioni attendibili: questi valori non garantiscono indicizzazione o posizionamento.

Il programma segnala gli errori su stderr e termina con codice 1 se l'input, gli URL o la scrittura non sono validi. La sitemap è limitata a 50.000 elementi e 50 MB non compressi; non vengono generati indici per raccolte più grandi.

## Verifica

```sh
npm test
```

I test eseguono la CLI, leggono l'XML con un parser e controllano escaping, deduplicazione, creazione delle directory e gestione degli errori.
