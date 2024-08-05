#!/bin/zsh

# Directory della cache dell'utente
CACHE_DIR="/Users/andbardii/Library/Caches"

# Pulizia della cache dell'utente
echo "Svuotamento della cache in $CACHE_DIR..."
find $CACHE_DIR -type f -delete
find $CACHE_DIR -type d -empty -delete

# Pulizia della RAM
echo "Pulizia della RAM..."
sudo purge

# Rimuovere file di log vecchi
echo "Rimuovere file di log vecchi..."
sudo find /private/var/log -type f -name "*.log" -exec rm -f {} \;

# Pulizia della cache del sistema
SYSTEM_CACHE_DIR="/Library/Caches"
EXCLUDE_DIRS=("com.apple.aned" "com.apple.aneuserd" "com.apple.iconservices.store" "com.apple.amsengagementd.classicdatavault")

echo "Pulizia della cache del sistema con esclusioni..."
for dir in "$SYSTEM_CACHE_DIR"/*; do
    dir_name=$(basename "$dir")
    if [[ ! " ${EXCLUDE_DIRS[@]} " =~ " ${dir_name} " ]]; then
        sudo find "$dir" -type f -delete
        sudo find "$dir" -type d -empty -delete
    fi
done

echo "Ottimizzazione completata!"