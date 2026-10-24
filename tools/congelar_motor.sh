#!/bin/zsh
# congelar_motor.sh — empacota o motor (teleporte.py --ipc) num executável com Python, MediaPipe e o som,
# pra ir dentro do Ilusio.app (quem baixa o app não precisa de Python nem do setup.sh).
# Uso: tools/congelar_motor.sh   (PYTHON=caminho/do/python pra usar outro venv)
set -euo pipefail
cd "${0:A:h}/.."
PY="${PYTHON:-.venv/bin/python}"
[ -f sons/teleport.wav ] || "$PY" tools/preparar_som.py
rm -rf build/engine
"$PY" -m PyInstaller --noconfirm --clean --log-level WARN --onedir --name ilusio-engine \
  --distpath build/engine/dist --workpath build/engine/work --specpath build/engine \
  --collect-data mediapipe --collect-binaries mediapipe \
  --add-data "$PWD/sons/teleport.wav:sons" \
  --exclude-module tkinter --exclude-module matplotlib \
  teleporte.py
# carimbo das fontes: o build Release do app recusa um motor congelado de código antigo
shasum -a 256 teleporte.py ipc.py requirements.txt sons/teleport.wav | shasum -a 256 | cut -d' ' -f1 \
  > build/engine/dist/ilusio-engine/.fontes
echo "Pronto: build/engine/dist/ilusio-engine ($(du -sh build/engine/dist/ilusio-engine | cut -f1))"
