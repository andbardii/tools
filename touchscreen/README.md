# Touchscreen

Fa funzionare su macOS i touchscreen USB generici (digitizer HID, es. QDtech) che il sistema riconosce ma non usa: il tocco diventa movimento e click del cursore sullo schermo scelto. Solo tocco singolo (tap, trascinamento), niente gesti multitouch.

## Uso

```sh
node touchscreen.mjs start     # elenca gli schermi, chiede quale è il touchscreen e parte
node touchscreen.mjs scegli    # richiede la scelta anche se già memorizzata
node touchscreen.mjs stop
node touchscreen.mjs status
node touchscreen.mjs list      # elenca gli schermi con id e nome
```

Al primo avvio chiede quale schermo è il touch e lo ricorda (per nome) in `~/.config/touchscreen.json`; dopo parte da solo con quello. Se lo schermo non è più collegato, chiede di nuovo.

Per forzare uno schermo senza chiedere: `TOUCH_SCREEN=<parte del nome> node touchscreen.mjs start` oppure `TOUCH_DISPLAY=<id>`.

## Permessi

Il driver è un'app (`~/Applications/Touchscreen.app`, compilata al primo avvio da `driver.swift`). In Impostazioni di Sistema > Privacy e sicurezza consenti a **Touchscreen** sia **Monitoraggio input** sia **Accessibilità** (trascina l'app nella lista, `open -R ~/Applications/Touchscreen.app` la mostra in Finder). Ogni ricompilazione cambia la firma e fa perdere i permessi: vanno riattivati.

## Requisiti

macOS con Xcode Command Line Tools (`swiftc`) e Node.js.
