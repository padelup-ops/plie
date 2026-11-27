#!/bin/bash
# App Switch sans ordinateur : compile l'émulateur (MeloNX) et StikDebug (qui active le JIT ; AGPL v3), puis les signe
# « développement » pour un iPhone précis avec le compte développeur. Les deux .ipa signées sortent dans
# retrofold/Switch/ ; elles ne s'installent que sur cet iPhone et ne passent pas par la vérification d'Apple.
# Usage : switch_install.sh UDID   (variables de switch_sign.py pour le compte développeur)
set -euo pipefail
UDID=${1:?"il manque l identifiant (UDID) de l iPhone"}
STIK_REPO=https://github.com/StikDebug/StikDebug.git
STIK_REV=63713ea2100660dc7066ee0e8d962858026f97aa
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT="$HERE/Switch"
WORK=${WORK:-$(mktemp -d)}
# SIGN_DIR : un dossier gardé d'une fois sur l'autre (certificat et sa clé), pour ne pas en créer un à chaque signature.
SIGN=${SIGN_DIR:-$WORK/signature}
# APPS : « switch », « stikdebug » ou les deux.
APPS=${APPS:-switch stikdebug}
mkdir -p "$OUT" "$SIGN"
want() { case " $APPS " in *" $1 "*) return 0;; *) return 1;; esac; }

if want switch; then
echo "=== Émulateur Switch"
WORK="$WORK/melonx-build" bash "$HERE/tools/build_switch.sh"
fi

if want stikdebug; then
echo "=== StikDebug ($STIK_REV)"
mkdir -p "$WORK/stik" && cd "$WORK/stik"
git init -q && git remote add origin "$STIK_REPO"
git fetch -q --depth 1 origin "$STIK_REV" && git checkout -q FETCH_HEAD
xcodebuild clean archive -project StikDebug.xcodeproj -scheme StikDebug -configuration Debug \
  -archivePath "$WORK/StikDebug.xcarchive" -sdk iphoneos -destination 'generic/platform=iOS' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO SWIFT_OPTIMIZATION_LEVEL="-Onone" \
  IPHONEOS_DEPLOYMENT_TARGET=17.4 | grep -E "error|ARCHIVE (SUCCEEDED|FAILED)" || true
[ -d "$WORK/StikDebug.xcarchive/Products/Applications/StikDebug.app" ] || { echo "StikDebug n'a pas été produite"; exit 1; }
fi

echo "=== Compte développeur"
python3 "$HERE/tools/switch_sign.py" preparer "$UDID" "$SIGN"

echo "=== Signature"
KEYCHAIN="$WORK/retrofold-switch.keychain-db"
security create-keychain -p retrofold "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p retrofold "$KEYCHAIN"
security import "$SIGN/signature.p12" -k "$KEYCHAIN" -P retrofold -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k retrofold "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk 'NR==1 {print $2}')
[ -n "$IDENTITY" ] || { echo "Pas d'identité de signature dans le trousseau"; security find-identity -v "$KEYCHAIN"; exit 1; }

sign_app() { # $1 clé (switch | stikdebug), $2 dossier .app, $3 nom de l'.ipa
  local key=$1 app=$2 ipa=$3 stage="$WORK/stage-$1"
  rm -rf "$stage"; mkdir -p "$stage/Payload"
  ditto "$app" "$stage/Payload/$(basename "$app")"
  app="$stage/Payload/$(basename "$app")"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(cat "$SIGN/$key.bundleid")" "$app/Info.plist"
  cp "$SIGN/$key.mobileprovision" "$app/embedded.mobileprovision"
  # Les droits de l'app sont ceux du profil (débogage autorisé, et mémoire étendue pour l'émulateur).
  security cms -D -i "$SIGN/$key.mobileprovision" > "$stage/profil.plist"
  /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$stage/profil.plist" > "$stage/droits.plist"
  # Une extension demanderait son propre profil : on s'en passe.
  if [ -d "$app/PlugIns" ]; then echo "note : extensions retirées de $(basename "$app") : $(ls "$app/PlugIns" | tr '\n' ' ')"; rm -rf "$app/PlugIns"; fi
  find "$app" -name "_CodeSignature" -type d -prune -exec rm -rf {} +
  # Le code embarqué d'abord (du plus profond au moins profond), l'app en dernier.
  find "$app" \( -name "*.dylib" -o -name "*.framework" \) -print | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2- | while read -r item; do
    codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" --timestamp=none "$item"
  done
  codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" --timestamp=none --entitlements "$stage/droits.plist" "$app"
  codesign --verify --deep --strict "$app" && echo "ok     signature vérifiée : $(basename "$app")"
  codesign -d --entitlements :- "$app" 2>/dev/null | grep -E -A1 "get-task-allow|increased-memory-limit" | tr -d '\n\t' | sed 's/^/droits : /'; echo
  (cd "$stage" && zip -qry "$OUT/$ipa" Payload)
  du -sh "$OUT/$ipa"
}

if want switch; then
  mkdir -p "$WORK/unsigned" && (cd "$WORK/unsigned" && unzip -q -o "$OUT/RetroFoldSwitch.ipa")
  sign_app switch "$WORK/unsigned/Payload/MeloNX.app" RetroFoldSwitch-signee.ipa
fi
if want stikdebug; then
  sign_app stikdebug "$WORK/StikDebug.xcarchive/Products/Applications/StikDebug.app" RetroFoldStikDebug-signee.ipa
fi
security delete-keychain "$KEYCHAIN"
[ -n "${SIGN_DIR:-}" ] || rm -rf "$SIGN"
