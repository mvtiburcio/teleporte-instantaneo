#!/bin/zsh
# build.sh — compila o "Ilusio Mic": o driver de áudio do BlackHole (GPL-3, Existential Audio) com nome e
# identificador do Ilusio. O código do BlackHole não fica neste repositório: é baixado na versão fixada abaixo.
# Uso: app/IlusioMic/build.sh [identidade de assinatura]   (padrão: ad-hoc "-"; o build do app passa a mesma identidade dele)
set -euo pipefail
cd "${0:A:h}"

BLACKHOLE_TAG=v0.7.2
BLACKHOLE_COMMIT=561d934c77a1fa64987e01ccabe890fed30e181f  # conferido: o tag precisa apontar pra este commit
BUNDLE_ID=com.mvtiburcio.ilusio.mic
DRIVER_BUILD=597  # 596 era o BlackHole puro; 597: transport USB
IDENTITY="${1:--}"
TEAM="${DEVELOPMENT_TEAM:-}"

rm -rf build && mkdir -p build
git clone -q --depth 1 --branch "$BLACKHOLE_TAG" https://github.com/ExistentialAudio/BlackHole.git build/src
[ "$(git -C build/src rev-parse HEAD)" = "$BLACKHOLE_COMMIT" ] || { echo "BlackHole $BLACKHOLE_TAG não bate com o commit fixado" >&2; exit 1; }

# o WhatsApp (app de iPad, pilha de áudio do iOS) não lista microfone "Virtual"; como USB ele aparece
c=build/src/BlackHole/BlackHole.c
[ "$(grep -c kAudioDeviceTransportTypeVirtual $c)" = 2 ] || { echo "BlackHole.c mudou: revisar o patch do transport" >&2; exit 1; }
sed -i '' 's/kAudioDeviceTransportTypeVirtual/kAudioDeviceTransportTypeUSB/' $c
# o app reinstala o driver quando esta versão difere da instalada: subir a cada mudança no driver
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $DRIVER_BUILD" build/src/BlackHole/BlackHole.plist

# ícone do Ilusio no driver (aparece no Configuração de Áudio e MIDI)
icons=../Ilusio/Assets.xcassets/AppIcon.appiconset
mkdir -p build/Ilusio.iconset
for f in $icons/icon_*.png; do cp "$f" build/Ilusio.iconset/; done
iconutil -c icns build/Ilusio.iconset -o build/src/BlackHole/IlusioMic.icns
cp build/src/BlackHole/IlusioMic.icns build/src/BlackHole/BlackHole.icns  # o projeto do BlackHole empacota este nome

# ambiente limpo: chamado de dentro do build do app, o xcodebuild herdaria variáveis do Xcode de fora
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" \
xcodebuild -quiet -project build/src/BlackHole.xcodeproj -configuration Release -target BlackHole \
  CONFIGURATION_BUILD_DIR="$PWD/build/out" \
  PRODUCT_NAME=IlusioMic PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM=$TEAM \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp \
  GCC_PREPROCESSOR_DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS
  kDriver_Name=\"IlusioMic\"
  kPlugIn_BundleID=\"'$BUNDLE_ID'\"
  kPlugIn_Icon=\"BlackHole.icns\"
  kDevice_Name=\"Ilusio\ Mic\"
  kManufacturer_Name=\"Ilusio\"
  kNumber_Of_Channels=2'

cp build/src/LICENSE build/out/IlusioMic.driver/Contents/Resources/LICENSE-BlackHole-GPL3.txt
echo "Pronto: $PWD/build/out/IlusioMic.driver (BlackHole $BLACKHOLE_TAG, GPL-3)"
