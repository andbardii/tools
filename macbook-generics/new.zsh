#!/bin/zsh

# Funzione per controllare se un comando esiste
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Aggiornare e installare xcode-select (necessario per Homebrew)
echo "Updating xcode-select..."
xcode-select --install 2>/dev/null

# Installare Homebrew se non è già installato
if ! command_exists brew; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew is already installed"
fi

# Aggiungere Homebrew al PATH se non è già presente
if ! grep -q 'eval "$(/opt/homebrew/bin/brew shellenv)"' ~/.zprofile; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Installare Git se non è già installato
if ! command_exists git; then
    echo "Installing Git..."
    brew install git
else
    echo "Git is already installed"
fi

# Installare Node.js se non è già installato
if ! command_exists node; then
    echo "Installing Node.js..."
    brew install node
else
    echo "Node.js is already installed"
fi

# Verificare le installazioni
echo "Verifying installations..."
echo "Homebrew version: $(brew --version)"
echo "Git version: $(git --version)"
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

echo "System configuration completed successfully!"
