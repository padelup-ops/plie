#!/bin/bash
# Ajoute le cœur de SameBoy (licence Expat/MIT) et ses ROM de démarrage libres au paquet GBCore, avant la compilation.
# Version fixée. Les ROM de démarrage sont assemblées depuis leurs sources (rgbds), puis mises dans un en-tête C.
set -euo pipefail
REV=ea667ad79aa28409f034b1fd6da7304e1844750d
HERE=$(cd "$(dirname "$0")/.." && pwd)
DEST="$HERE/GBCore/Sources/GBCore"
TMP=$(mktemp -d)
git clone -q https://github.com/LIJI32/SameBoy.git "$TMP/sb"
git -C "$TMP/sb" checkout -q "$REV"
rm -rf "$DEST/Core"
mkdir -p "$DEST/Core"
cp -R "$TMP/sb/Core/." "$DEST/Core/"
cp "$TMP/sb/LICENSE" "$DEST/Core/LICENSE"
# Pas compilés (désactivés) : débogueur, triche, retour en arrière.
rm -f "$DEST"/Core/{debugger.c,sm83_disassembler.c,symbol_hash.c,cheats.c,cheat_search.c,rewind.c}
command -v rgbasm >/dev/null || brew install rgbds >/dev/null
make -C "$TMP/sb" "build/bin/BootROMs/dmg_boot.bin" "build/bin/BootROMs/cgb_boot.bin" >/dev/null
python3 - "$TMP/sb/build/bin/BootROMs" "$DEST/bootroms.h" <<'PY'
import sys, os
src, out = sys.argv[1], sys.argv[2]
with open(out, "w") as f:
    f.write("// ROM de démarrage libres de SameBoy (licence Expat/MIT), générées par fetch_sameboy.sh.\n#pragma once\n")
    for name in ("dmg_boot", "cgb_boot"):
        data = open(os.path.join(src, name + ".bin"), "rb").read()
        f.write(f"static const unsigned char {name}_bin[{len(data)}] = {{" + ",".join(str(b) for b in data) + "};\n")
print("boot ROMs", os.path.getsize(out))
PY
ls "$DEST/Core" | wc -l
