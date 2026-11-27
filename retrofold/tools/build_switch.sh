#!/bin/bash
# Compile l'émulateur Switch libre MeloNX (AGPL v3, basé sur Ryujinx) en .ipa non signée, pour un usage personnel :
# cette app ne part ni sur TestFlight ni sur l'App Store (elle a besoin du JIT, qu'Apple n'accorde pas aux apps distribuées).
# Source : une copie publique du projet sur GitHub, à une version fixée. Rien de Nintendo n'est inclus : ni clés, ni
# firmware, ni jeux. Sortie : retrofold/Switch/RetroFoldSwitch.ipa et les droits à donner à la signature.
set -euo pipefail
REPO=${SWITCH_REPO:-https://github.com/AzureDominus/melonx.git}
REV=${SWITCH_REV:-55f84af15144e40d7fbe8984747855534d2a8ec1}
BUNDLE_ID=${BUNDLE_ID:-com.padelup.retrofold.switch}
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT="$HERE/Switch"
WORK=${WORK:-$(mktemp -d)}
SRC="$WORK/melonx"
mkdir -p "$OUT"

echo "=== Outils"
command -v git-lfs >/dev/null || brew install git-lfs >/dev/null
git lfs install --skip-repo >/dev/null
# .NET 8 (le cœur Ryujinx est en C#, compilé d'avance en bibliothèque native) : là où le projet le cherche.
# Le projet demande .NET 8 (global.json) : on l'ajoute s'il manque, à côté des versions déjà là.
export DOTNET_ROOT="$HOME/.dotnet" PATH="$HOME/.dotnet:$PATH" DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
if ! dotnet --list-sdks 2>/dev/null | grep -q '^8\.0\.'; then
  curl -sSL https://dot.net/v1/dotnet-install.sh -o "$WORK/dotnet-install.sh"
  bash "$WORK/dotnet-install.sh" --channel 8.0 --install-dir "$HOME/.dotnet" | tail -2
fi
dotnet --list-sdks | sed 's/^/SDK .NET /'
dotnet workload install ios 2>&1 | tail -3

echo "=== Sources ($REV)"
rm -rf "$SRC"; mkdir -p "$SRC"; cd "$SRC"
git init -q
git remote add origin "$REPO"
git fetch -q --depth 1 origin "$REV"
git checkout -q FETCH_HEAD
echo "=== Version des sources : $(git rev-parse HEAD) $(git log -1 --format=%cs)"
git lfs pull
ls -la "src/MeloNX/MeloNX/Dependencies/Dynamic Libraries"

echo "=== Compilation"
PROJECT=src/MeloNX/MeloNX.xcodeproj
LIBDEPS="$WORK/libdeps"
ln -sfn "$SRC/src/MeloNX/MeloNX/Dependencies/Dynamic Libraries" "$LIBDEPS"
xcodebuild -project "$PROJECT" -scheme MeloNX -resolvePackageDependencies | tail -3
xcodebuild -project "$PROJECT" -scheme MeloNX -configuration Release -sdk iphoneos \
  -destination "generic/platform=iOS" -derivedDataPath "$WORK/dd" clean build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES ONLY_ACTIVE_ARCH=NO \
  "LIBRARY_SEARCH_PATHS=\$(inherited) $LIBDEPS" \
  "OTHER_LDFLAGS=\$(inherited) $LIBDEPS/Ryujinx.Headless.SDL2.dylib"

echo "=== Paquet"
APP=$(find "$WORK/dd/Build/Products/Release-iphoneos" -maxdepth 1 -name 'MeloNX.app' -type d -print -quit)
[ -n "$APP" ] || { echo "MeloNX.app n'a pas été produite"; exit 1; }
DYLIB="$SRC/src/MeloNX/MeloNX/Dependencies/Dynamic Libraries/Ryujinx.Headless.SDL2.dylib"
[ -f "$DYLIB" ] || DYLIB=$(find "$SRC/src/Ryujinx.Headless.SDL2" -name 'Ryujinx.Headless.SDL2.dylib' -type f -print -quit)
[ -n "$DYLIB" ] && [ -f "$DYLIB" ] || { echo "Ryujinx.Headless.SDL2.dylib n'a pas été produite"; exit 1; }
mkdir -p "$APP/Frameworks"
ditto "$DYLIB" "$APP/Frameworks/Ryujinx.Headless.SDL2.dylib"
chmod 755 "$APP/Frameworks/Ryujinx.Headless.SDL2.dylib"
# Un identifiant à nous, pour pouvoir la signer avec notre compte développeur.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$APP/Info.plist"
ls "$APP/Frameworks"
rm -rf "$WORK/ipa"; mkdir -p "$WORK/ipa/Payload"
ditto "$APP" "$WORK/ipa/Payload/MeloNX.app"
(cd "$WORK/ipa" && zip -qry "$OUT/RetroFoldSwitch.ipa" Payload)
cp "$SRC/src/MeloNX/MeloNX/MeloNX.entitlements" "$OUT/entitlements.plist"
cp "$SRC/LICENSE.txt" "$OUT/LICENSE-MeloNX.txt"
du -sh "$OUT/RetroFoldSwitch.ipa"
