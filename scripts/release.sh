#!/bin/zsh
# release.sh — gera o Ilusio-<versão>.dmg assinado com o Developer ID da TKI, notarizado e grampeado,
# e cria a release no GitHub como RASCUNHO (quem publica é uma pessoa, depois de conferir).
# Uso: scripts/release.sh 0.1.0 [--sem-notarizar] [--sem-publicar]
# Pré-requisitos: certificado "Developer ID Application" da TKI no Keychain, perfil do notarytool
# "ilusio-notary" (xcrun notarytool store-credentials), .venv-release (Python do uv, ver README) com requirements-dev.txt e gh logado.
set -euo pipefail
cd "${0:A:h}/.."

VERSION="${1:?uso: scripts/release.sh <versão> [--sem-notarizar] [--sem-publicar]}"
shift
NOTARIZE=1; PUBLISH=1
for arg in "$@"; do
  case $arg in
    --sem-notarizar) NOTARIZE=0; PUBLISH=0 ;;  # sem notarização não se publica
    --sem-publicar) PUBLISH=0 ;;
    *) echo "opção desconhecida: $arg" >&2; exit 1 ;;
  esac
done
TEAM=73928LZ8Q7
IDENTITY="Developer ID Application: TKI TECNOLOGIA LTDA ($TEAM)"
PROFILE=ilusio-notary
PY="${PYTHON:-.venv-release/bin/python}"  # Python do uv (README): o do Homebrew não abre em macOS mais antigo
OUT="$PWD/build/release"
DMG="$OUT/Ilusio-$VERSION.dmg"
BUILD=$(git rev-list --count HEAD)
REPO_URL=https://github.com/mvtiburcio/teleporte-instantaneo

security find-identity -v -p codesigning | grep -q "$IDENTITY" || { echo "falta o certificado: $IDENTITY" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "há mudanças não commitadas: o release sai só de código versionado" >&2; exit 1; }
rm -rf "$OUT" && mkdir -p "$OUT"

# assina cada Mach-O da pasta individualmente e o executável principal por último (com os entitlements),
# tudo com hardened runtime e carimbo de tempo
sign_tree() {
  local dir=$1 main=$2
  find "$dir" -type f | while read -r f; do
    file -b "$f" | grep -q "Mach-O" || continue
    [ "$f" = "$main" ] && continue
    codesign -f -s "$IDENTITY" --options runtime --timestamp "$f"
  done
  codesign -f -s "$IDENTITY" --options runtime --timestamp --entitlements scripts/engine.entitlements "$main"
}

echo "==> 1/6 motor congelado"
PYTHON="$PY" tools/congelar_motor.sh
sign_tree build/engine/dist/ilusio-engine build/engine/dist/ilusio-engine/ilusio-engine

echo "==> 2/6 Ilusio Mic"
rm -rf app/IlusioMic/build
DEVELOPMENT_TEAM=$TEAM app/IlusioMic/build.sh "$IDENTITY"

echo "==> 3/6 app (archive + export Developer ID)"
(cd app && xcodegen generate -q)
xcodebuild -quiet archive -project app/Ilusio.xcodeproj -scheme Ilusio -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$OUT/Ilusio.xcarchive" \
  -allowProvisioningUpdates -clonedSourcePackagesDirPath "$PWD/build/spm" MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD"  # build crescente: sem ele o macOS não troca a câmera nem o Sparkle vê a versão nova
xcodebuild -quiet -exportArchive -archivePath "$OUT/Ilusio.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates
APP="$OUT/export/Ilusio.app"
codesign --verify --deep --strict "$APP"
sig=$(codesign -dvv "$APP" 2>&1)  # sem pipe: com pipefail, o grep -q cortaria o codesign (SIGPIPE)
[[ $sig == *"Authority=Developer ID Application"* ]] || { echo "app não saiu com Developer ID" >&2; exit 1; }

if [ $NOTARIZE = 1 ]; then
  echo "==> 4/6 notarização do app"
  ditto -c -k --keepParent "$APP" "$OUT/Ilusio.zip"
  xcrun notarytool submit "$OUT/Ilusio.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
fi

echo "==> 5/6 dmg"
mkdir -p "$OUT/dmg" && ditto "$APP" "$OUT/dmg/Ilusio.app" && ln -s /Applications "$OUT/dmg/Aplicativos"
cp LICENSE "$OUT/dmg/Licença.txt" && cp NOTICE.md "$OUT/dmg/Avisos.md"  # a licença acompanha o binário
hdiutil create -quiet -volname "Ilusio $VERSION" -srcfolder "$OUT/dmg" -fs HFS+ -format UDZO "$DMG"
codesign -s "$IDENTITY" --timestamp "$DMG"
if [ $NOTARIZE = 1 ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
fi
(cd "$OUT" && shasum -a 256 "${DMG:t}" | tee "${DMG:t}.sha256")  # só o nome: o caminho local não vai pro arquivo público

# feed do Sparkle: o app lê releases/latest/download/appcast.xml, então só vale depois que a release é publicada.
# A assinatura EdDSA usa a chave privada do Keychain (generate_keys do Sparkle; sem ela não há atualização).
SIG=$(build/spm/artifacts/sparkle/Sparkle/bin/sign_update "$DMG")
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Ilusio</title>
    <item>
      <title>Ilusio $VERSION</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$REPO_URL/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$REPO_URL/releases/download/v$VERSION/${DMG:t}" $SIG type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

if [ $PUBLISH = 1 ]; then
  echo "==> 6/6 release no GitHub (rascunho)"
  # a tag nasce no commit compilado, não na ponta da main de quando o rascunho for publicado
  [ -n "$(git branch -r --contains HEAD)" ] || { echo "faça push deste commit antes de publicar" >&2; exit 1; }
  gh release create "v$VERSION" "$DMG" "$DMG.sha256" "$OUT/appcast.xml" --draft --target "$(git rev-parse HEAD)" --title "Ilusio $VERSION" \
    --notes "Já tem o Ilusio 0.1.3 ou mais novo? Ele se atualiza sozinho (ou em Ilusio ▸ Buscar atualizações…).

Primeira instalação: baixe o Ilusio-$VERSION.dmg, arraste o Ilusio para Aplicativos e abra. O app guia o resto (câmera e microfone do Ilusio, fundo, gesto). macOS 26+, Apple Silicon.

Windows 10/11 x64: baixe o Ilusio-Setup-$VERSION.exe. Sem assinatura, o Windows avisa no primeiro uso: Mais informações → Executar assim mesmo."
  # o instalador do Windows sai do CI (a partir da main) e entra neste mesmo rascunho: publique só depois que ele aparecer
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || echo "aviso: o instalador do Windows sai da main, não deste commit" >&2
  gh workflow run windows.yml --ref main -f version="$VERSION"
  echo "Acompanhe o instalador do Windows: gh run watch \$(gh run list --workflow windows.yml --limit 1 --json databaseId -q '.[0].databaseId')"
fi
echo "Pronto: $DMG"
