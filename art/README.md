# Art

Piccolo studio locale per ambientare la foto di un quadro su una parete ed esportarla per Instagram. Nessuna dipendenza, account o upload: le immagini vengono elaborate nel browser e non lasciano questo computer. Richiede Node.js 18 o successivo e un browser moderno.

```sh
run art
stop art
```

Dopo l'installazione dei comandi shell, apri un nuovo terminale oppure esegui `source ~/.zshrc`.

Avvio alternativo da questa cartella: `node art.mjs start`; arresto: `node art.mjs stop`. `ART_PORT=4401 run art` cambia porta (usa la stessa porta per stop). `npm start` esegue il server in primo piano.

## Cataloghi di foto collegati

Nella sezione **Cataloghi** puoi collegare una o più cartelle di foto del Mac e scegliere il quadro (o lo sfondo) direttamente da lì, senza ricaricarlo a mano.

- **＋ Collega cartella** apre la finestra di scelta di macOS.
- Si sfogliano le sottocartelle, si cerca per nome e si sceglie se usare la foto come **Quadro** o **Sfondo**. Le anteprime sono miniature generate con `sips` e tenute in `~/.cache/art/anteprime`; l'esportazione usa sempre il file originale.
- I collegamenti stanno in `~/.config/art/cataloghi.json`. **Scollega** toglie solo il collegamento: cartelle e foto non vengono toccate. Art legge e basta, non scrive mai nelle cartelle collegate.
- Formati: JPG, PNG, WebP. Il server ascolta solo su `127.0.0.1`, controlla l'intestazione `Host` e rifiuta ogni percorso fuori dalle cartelle collegate (anche tramite link simbolici).

## Utilizzo

Carica una foto già ritagliata ai bordi dell'opera (JPG, PNG o WebP). Scegli mattoni, bianco o uno sfondo personale; seleziona post quadrato, storia o post verticale. Regola dimensione, ombra e luminosità del solo quadro (100% mantiene l’originale, fino a 170% per schiarire). Il pulsante Ripristina luminosità riporta al 100%. La regolazione viene applicata anche al PNG esportato. Trascina il quadro, oppure seleziona l'anteprima con Tab e usa le frecce (Shift per passi più grandi). Il quadro mantiene le proporzioni ed è contenuto nella composizione.

Esporta in PNG senza perdita a 1×, 2× o 4×:

| Formato | Standard | Alta | Massima |
| --- | --- | --- | --- |
| Quadrato | 1080 × 1080 | 2160 × 2160 | 4320 × 4320 |
| Storia | 1080 × 1920 | 2160 × 3840 | 4320 × 7680 |
| Verticale | 1080 × 1350 | 2160 × 2700 | 4320 × 5400 |

L'esportazione legge l'immagine originale, non l'anteprima ridotta. Se la foto viene ingrandita compare un avviso: più pixel esportati non ricreano dettagli assenti nella sorgente. Anche lo sfondo fornito conserva la sua risoluzione originale; riempiendo il formato può essere ritagliato e ingrandito. L'ombra è ampia verso sinistra, più scura vicino al quadro e sfumata all'esterno, senza riempimento o bordo attorno all'opera, ispirata all'esempio fornito. Non include rimozione automatica dello sfondo, correzione prospettica o ritaglio dell'opera. Le composizioni non vengono conservate dopo il ricaricamento della pagina.

Il server ascolta solo su questo computer (`127.0.0.1`, porta 4322). I comandi di avvio e arresto verificano il processo del server prima di riutilizzarlo o terminarlo. Log e PID sono nella cartella temporanea di macOS.

Verifica sintassi: `npm run check`.
