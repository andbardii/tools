# MacBook Generics

Script Zsh per preparare e controllare un Mac da sviluppo, sia Apple Silicon sia Intel. Il piano predefinito non installa software e non cambia configurazioni.

## Preparazione

```sh
zsh new.zsh               # mostra gli strumenti mancanti
zsh new.zsh --apply       # installa solo quelli mancanti
zsh new.zsh --apps        # include nel piano VS Code, Docker e Codex CLI
zsh new.zsh --apply --apps
```

Richiede macOS, Command Line Tools e [Homebrew](https://docs.brew.sh/Installation). Se mancano i Command Line Tools, `--apply` apre l'installer Apple e interrompe la preparazione: completarlo prima di rilanciare. Homebrew va installato dalle istruzioni ufficiali. Lo script riconosce anche le installazioni standard non presenti nel PATH; non modifica `.zprofile` o `.zshrc`.

Gli strumenti base sono Git, GitHub CLI, ripgrep, jq e uv. Conserva Node già disponibile, inclusi ambienti nvm, e non sostituisce Python/pyenv. Se Node manca, installa fnm e la versione LTS, poi mostra la riga da aggiungere alla shell. Nei progetti rispettare `.nvmrc`, `.node-version` e le versioni richieste; Angular/React e i relativi CLI restano dipendenze del progetto. Per Python usare ambienti isolati con `uv venv` e, se necessario, `uv python install`.

`--apps` è facoltativo: non reinstalla app rilevate in `/Applications` o cask già installati. Per Codex CLI controlla anche il comando `codex` nel PATH; l’app desktop è distinta e non viene installata dallo script. Docker non viene avviato e Codex/GitHub non vengono autenticati. Non vengono installati servizi, database o pacchetti npm globali.

## Manutenzione

```sh
zsh optimizer.zsh                        # spazio e memoria, sola lettura
zsh optimizer.zsh --brew-cleanup         # anteprima Homebrew
zsh optimizer.zsh --brew-cleanup --apply # rimuove le vecchie cache/versioni gestite da Homebrew
```

La pulizia è limitata a [`brew cleanup`](https://docs.brew.sh/Manpage#cleanup-options-formulacask-): leggere l'anteprima prima di applicarla. Non elimina cache delle applicazioni, log di sistema, volumi Docker o dipendenze dei progetti. Non usa `sudo purge`: la gestione della memoria resta a macOS. Non aggiorna o rimuove automaticamente pacchetti inutilizzati.

Entrambi accettano `--help` e rifiutano opzioni sconosciute. `--dry-run` ripristina la modalità di anteprima; se passato insieme a `--apply`, vale l'ultima opzione. Per controllare la sintassi senza eseguire operazioni:

```sh
zsh -n new.zsh optimizer.zsh
```
