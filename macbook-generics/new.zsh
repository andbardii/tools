#!/bin/zsh
# Configurazione esplicita: la modalità predefinita mostra soltanto il piano.
set -euo pipefail
apply=false
apps=false
for arg in "$@"; do
  case "$arg" in
    --apply) apply=true ;;
    --dry-run) apply=false ;;
    --apps) apps=true ;;
    --help|-h) print 'Uso: zsh new.zsh [--dry-run|--apply] [--apps]'; exit 0 ;;
    *) print -u2 -- "Opzione sconosciuta: $arg"; exit 2 ;;
  esac
done
[[ $(uname -s) == Darwin ]] || { print -u2 'Questo script richiede macOS.'; exit 1; }
run() {
  if $apply; then "$@"; else printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; fi
}
# Cerca anche Homebrew non ancora caricato nella shell corrente.
brew_bin=$(command -v brew || true)
if [[ -z $brew_bin ]]; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x $candidate ]]; then brew_bin=$candidate; break; fi
  done
fi
if ! xcode-select -p >/dev/null 2>&1; then
  print 'Command Line Tools mancanti: installarle, completare la finestra e rilanciare.'
  run xcode-select --install
  exit 0
fi
if [[ -z $brew_bin ]]; then
  print 'Homebrew mancante. Installarlo seguendo https://docs.brew.sh/Installation e rilanciare.'
  exit 1
fi
# Imposta PATH solo per questo processo: non sovrascrive i profili personali.
eval "$("$brew_bin" shellenv)"
install_formula() {
  if "$brew_bin" list --formula "$1" >/dev/null 2>&1; then
    print -- "$1 già installato."
  else
    run "$brew_bin" install "$1"
  fi
}
for formula in git gh ripgrep jq; do install_formula "$formula"; done
# Rispetta ambienti nvm/pyenv/uv esistenti, evitando runtime duplicati.
if ! command -v node >/dev/null 2>&1; then
  install_formula fnm
  if $apply; then
    eval "$(fnm env --shell zsh)"
    fnm install --lts --use
    fnm default "$(fnm current)"
  else
    print '[dry-run] fnm install --lts, poi imposta la versione installata come predefinita'
  fi
  print 'Per le nuove shell aggiungere a ~/.zshrc: eval "$(fnm env --use-on-cd --shell zsh)"'
fi
command -v uv >/dev/null 2>&1 || install_formula uv
if $apps; then
  for cask in visual-studio-code docker codex; do
    case $cask in
      visual-studio-code) app_path='/Applications/Visual Studio Code.app' ;;
      docker) app_path='/Applications/Docker.app' ;;
      codex)
        # Il cask codex installa la CLI; Codex.app è un prodotto distinto.
        if command -v codex >/dev/null 2>&1; then
          print 'Codex CLI già installata.'
          continue
        fi
        app_path=''
        ;;
    esac
    if [[ -n $app_path && -d $app_path ]] || "$brew_bin" list --cask "$cask" >/dev/null 2>&1; then
      print -- "$cask già installato."
    else
      run "$brew_bin" install --cask "$cask"
    fi
  done
fi
print 'Piano completato. Nessun login, servizio o pacchetto npm globale configurato.'
print 'Python per progetto: uv venv; uv python install (se necessario). Node già presente: rispettare .nvmrc/.node-version del progetto.'
