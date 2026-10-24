#!/bin/zsh
# setup.sh — instala tudo o que o teleporte precisa no macOS (Apple Silicon ou Intel)
set -e
cd "${0:A:h}"

if ! command -v brew >/dev/null; then
  echo "Instale o Homebrew primeiro: https://brew.sh" >&2
  exit 1
fi

echo "==> Python 3.12 (o MediaPipe não tem pacote para versões mais novas)"
brew list python@3.12 >/dev/null 2>&1 || brew install python@3.12

echo "==> OBS (fornece a câmera virtual)"
[ -d /Applications/OBS.app ] || brew install --cask obs

echo "==> BlackHole 2ch (placa de som virtual: leva o som do teleporte pra chamada; pede sua senha)"
if [ ! -d /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver ]; then
  brew install --cask blackhole-2ch
  echo "    Reiniciando o áudio do Mac pra carregar o BlackHole (pede sua senha)..."
  sudo killall coreaudiod || true
fi

echo "==> Ambiente Python"
[ -d .venv ] || "$(brew --prefix python@3.12)/bin/python3.12" -m venv .venv
.venv/bin/pip install -q -r requirements.txt

echo "==> Som do teleporte"
.venv/bin/python tools/preparar_som.py

chmod +x teleporte
cat <<'EOF'

Pronto! Falta só uma vez, manualmente:
  1. Abra o OBS, clique em "Iniciar câmera virtual" e aprove a extensão em
     Ajustes do Sistema > Geral > Itens de Início e Extensões > Extensões de Câmera.
  2. Clique em "Parar câmera virtual" e feche o OBS.
Depois disso, é só rodar: ./teleporte
EOF
