#!/bin/zsh
# build.sh — compila o "Ilusio Mic": o driver de áudio do BlackHole (GPL-3, Existential Audio) com nome e
# identificador do Ilusio. O código do BlackHole não fica neste repositório: é baixado na versão fixada abaixo.
# Uso: app/IlusioMic/build.sh [identidade de assinatura]   (padrão: ad-hoc "-"; o build do app passa a mesma identidade dele)
set -euo pipefail
cd "${0:A:h}"

BLACKHOLE_TAG=v0.7.2
BLACKHOLE_COMMIT=561d934c77a1fa64987e01ccabe890fed30e181f  # conferido: o tag precisa apontar pra este commit
BUNDLE_ID=com.mvtiburcio.ilusio.mic
DRIVER_BUILD=598  # 596 era o BlackHole puro; 598: mic USB só entrada + saída interna
IDENTITY="${1:--}"
TEAM="${DEVELOPMENT_TEAM:-}"

rm -rf build && mkdir -p build
git clone -q --depth 1 --branch "$BLACKHOLE_TAG" https://github.com/ExistentialAudio/BlackHole.git build/src
[ "$(git -C build/src rev-parse HEAD)" = "$BLACKHOLE_COMMIT" ] || { echo "BlackHole $BLACKHOLE_TAG não bate com o commit fixado" >&2; exit 1; }

# Dois dispositivos no mesmo ring buffer: "Ilusio Mic" só entrada, e "Ilusio Mic Interno" só saída, onde o
# motor escreve. O WhatsApp (app de iPad, pilha de áudio do iOS) esconde microfone "Virtual", então o Ilusio
# Mic se declara USB; e um USB com entrada e saída ele trata como headset e manda o alto-falante da chamada
# pra ele (ninguém ouve o outro lado, e a voz do outro volta pelo mic). Por isso a saída fica separada e Virtual.
c=build/src/BlackHole/BlackHole.c
sed -i '' '/TransportType for the device");/{n;s/kAudioDeviceTransportTypeVirtual/(inObjectID == kObjectID_Device ? kAudioDeviceTransportTypeUSB : kAudioDeviceTransportTypeVirtual)/;}' $c
[ "$(grep -c kAudioDeviceTransportTypeUSB $c)" = 1 ] || { echo "BlackHole.c mudou: revisar o patch do transport" >&2; exit 1; }
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
  kDevice_HasOutput=false
  kDevice2_Name=\"Ilusio\ Mic\ Interno\"
  kDevice2_IsHidden=false
  kDevice2_HasInput=false
  kManufacturer_Name=\"Ilusio\"
  kNumber_Of_Channels=2'

cp build/src/LICENSE build/out/IlusioMic.driver/Contents/Resources/LICENSE-BlackHole-GPL3.txt
echo "Pronto: $PWD/build/out/IlusioMic.driver (BlackHole $BLACKHOLE_TAG, GPL-3)"
