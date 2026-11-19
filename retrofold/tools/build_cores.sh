#!/bin/bash
# Compile les cœurs libretro de la Game Pak pour l'iPhone, en frameworks dynamiques chargés par l'app :
#   - MGBACore    : mGBA (Game Boy Advance), licence MPL 2.0, BIOS libre intégré
#   - MelonDSCore : melonDS DS (Nintendo DS), licence GPL v3, BIOS et firmware libres intégrés
# Versions fixées. Sortie : retrofold/Cores/{MGBACore,MelonDSCore}.framework
set -euo pipefail
MGBA_REV=7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6
MDS_REV=f394adbacb5722ee97c1b37c8064da9a25818310
MIN_IOS=17.0
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT="$HERE/Cores"
WORK=${WORK:-$(mktemp -d)}
mkdir -p "$OUT"
command -v cmake >/dev/null || brew install cmake
command -v ninja >/dev/null || brew install ninja
IOS_ARGS=(-G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS
          -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO)

framework() { # $1 dylib, $2 name, $3 bundle id, $4 version
  local fw="$OUT/$2.framework"
  rm -rf "$fw"; mkdir -p "$fw"
  cp "$1" "$fw/$2"
  install_name_tool -id "@rpath/$2.framework/$2" "$fw/$2"
  cat > "$fw/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>$2</string>
<key>CFBundleIdentifier</key><string>$3</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>$2</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>$4</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
<key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict></plist>
PL
  lipo -info "$fw/$2"; otool -L "$fw/$2" | head -8
  nm -gU "$fw/$2" | grep -c " _retro_" || true
}

if [ "${ONLY:-}" != ds ]; then
  echo "=== mGBA"
  rm -rf "$WORK/mgba"; git clone -q https://github.com/libretro/mgba.git "$WORK/mgba"; git -C "$WORK/mgba" checkout -q $MGBA_REV
  cmake -S "$WORK/mgba" -B "$WORK/mgba/build" "${IOS_ARGS[@]}" \
    -DBUILD_LIBRETRO=ON -DBUILD_QT=OFF -DBUILD_SDL=OFF -DBUILD_GL=OFF -DBUILD_GLES2=OFF -DBUILD_GLES3=OFF \
    -DBUILD_SHARED=OFF -DBUILD_STATIC=OFF -DBUILD_PERF=OFF -DBUILD_TEST=OFF -DBUILD_SUITE=OFF -DBUILD_CINEMA=OFF \
    -DBUILD_EXAMPLE=OFF -DBUILD_PYTHON=OFF -DBUILD_UPDATER=OFF -DSKIP_LIBRARY=ON -DUSE_FFMPEG=OFF -DUSE_ZLIB=OFF \
    -DUSE_MINIZIP=OFF -DUSE_PNG=OFF -DUSE_LIBZIP=OFF -DUSE_SQLITE3=OFF -DUSE_ELF=OFF -DUSE_LUA=OFF -DUSE_JSON_C=OFF \
    -DUSE_EDITLINE=OFF -DUSE_EPOXY=OFF -DUSE_DISCORD_RPC=OFF -DENABLE_SCRIPTING=OFF -DUSE_DEBUGGERS=OFF -DUSE_GDB_STUB=OFF \
    -DM_CORE_GB=OFF -DM_CORE_GBA=ON
  cmake --build "$WORK/mgba/build" --target mgba_libretro --parallel
  framework "$(find "$WORK/mgba/build" -name 'mgba_libretro*.dylib' | head -1)" MGBACore com.padelup.retrofold.mgba 0.11
fi

if [ "${ONLY:-}" != gba ]; then
  echo "=== melonDS DS"
  rm -rf "$WORK/mds"; git clone -q https://github.com/JesseTG/melonds-ds.git "$WORK/mds"; git -C "$WORK/mds" checkout -q $MDS_REV
  cmake -S "$WORK/mds" -B "$WORK/mds/build" "${IOS_ARGS[@]}" -DENABLE_JIT=OFF -DENABLE_OPENGL=OFF -DTRACY_ENABLE=OFF \
    -DBUILD_TESTING=OFF -Wno-deprecated
  cmake --build "$WORK/mds/build" --parallel
  framework "$(find "$WORK/mds/build" -name 'melondsds_libretro*.dylib' | head -1)" MelonDSCore com.padelup.retrofold.melonds 1.2
fi
ls -la "$OUT"
