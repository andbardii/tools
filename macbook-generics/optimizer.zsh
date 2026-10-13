#!/bin/zsh
# Diagnostica predefinita, pulizia limitata alla cache gestita da Homebrew.
set -euo pipefail
apply=false
cleanup=false
for arg in "$@"; do
  case "$arg" in
    --apply) apply=true ;;
    --dry-run) apply=false ;;
    --brew-cleanup) cleanup=true ;;
    --help|-h) print 'Uso: zsh optimizer.zsh [--dry-run|--apply] [--brew-cleanup]'; exit 0 ;;
    *) print -u2 -- "Opzione sconosciuta: $arg"; exit 2 ;;
  esac
done
[[ $(uname -s) == Darwin ]] || { print -u2 'Questo script richiede macOS.'; exit 1; }
print 'Spazio disponibile:'
df -h "$HOME"
print '\nMemoria virtuale (macOS gestisce autonomamente RAM e cache):'
vm_stat
brew_bin=$(command -v brew || true)
if [[ -z $brew_bin ]]; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x $candidate ]]; then brew_bin=$candidate; break; fi
  done
fi
if $cleanup; then
  if [[ -z $brew_bin ]]; then print -u2 'Homebrew non trovato.'; exit 1; fi
  # Evita aggiornamenti impliciti: questa operazione non aggiorna i pacchetti.
  export HOMEBREW_NO_AUTO_UPDATE=1
  if $apply; then "$brew_bin" cleanup; else "$brew_bin" cleanup --dry-run; fi
else
  print '\nPer vedere cosa Homebrew può rimuovere: zsh optimizer.zsh --brew-cleanup'
fi
