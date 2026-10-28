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
# o motor tem que abrir no macOS mínimo do app: o Python do Homebrew sai compilado pra versão do Mac
# que o instalou (27 → "Symbol not found: _dup3" no 26). Use o Python standalone do uv (mínimo 11).
MIN=26.0
find build/engine/dist/ilusio-engine -type f \( -perm -u+x -o -name '*.so' -o -name '*.dylib' -o -name Python \) |
while read -r f; do
  minos=$(otool -l "$f" 2>/dev/null | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit}')
  [ -n "$minos" ] && [ "$(printf '%s\n%s\n' "$minos" "$MIN" | sort -V | tail -1)" != "$MIN" ] &&
    { echo "$f pede macOS $minos (o app aceita $MIN): congele com o Python do uv (README)" >&2; exit 1; }
done
# carimbo das fontes: o build Release do app recusa um motor congelado de código antigo
shasum -a 256 teleporte.py ipc.py requirements.txt sons/teleport.wav | shasum -a 256 | cut -d' ' -f1 \
  > build/engine/dist/ilusio-engine/.fontes
echo "Pronto: build/engine/dist/ilusio-engine ($(du -sh build/engine/dist/ilusio-engine | cut -f1))"
