#!/bin/bash
# PS2, première pierre : l'émulateur libre Play! traduit le code des jeux en code machine (JIT), ce qu'une app de
# TestFlight ou de l'App Store n'a pas le droit de faire. Les fichiers de ce dossier remplacent ce code machine par un
# interpréteur (Jitter_CodeGen_Interp.*, Jitter_Interp_Execute.cpp, et codegen.patch qui le branche).
# Ce script le vérifie avec la suite de tests du générateur de code de Play!, sur Linux ou macOS : il échoue si un test échoue.
# Pas encore fait : le cœur PS2 lui-même pour l'iPhone, son affichage et ses commandes dans RetroFold.
set -euo pipefail
PLAY_REV=1f27232772e484bfb79364b751b84f41f4c87481
CODEGEN_REV=a5009f7dca062695b8e5aebbd71e67b4ddfa9251
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$(mktemp -d)}
mkdir -p "$WORK"
cd "$WORK"
[ ! -e play ] || { echo "$WORK/play existe déjà : choisis un dossier de travail vide"; exit 1; }
git init -q play && cd play
git remote add origin https://github.com/jpd002/Play-.git
git fetch -q --depth 1 origin "$PLAY_REV" && git checkout -q FETCH_HEAD
git submodule update -q --init --depth 1 deps/CodeGen deps/Framework deps/Dependencies
git -C deps/Dependencies submodule update -q --init --depth 1 zstd zlib ghc_filesystem xxHash
[ "$(git -C deps/CodeGen rev-parse HEAD)" = "$CODEGEN_REV" ] || { echo "Le générateur de code n'est pas à la version attendue"; exit 1; }
cp "$HERE/Jitter_CodeGen_Interp.h" deps/CodeGen/include/
cp "$HERE/Jitter_CodeGen_Interp.cpp" "$HERE/Jitter_Interp_Execute.cpp" deps/CodeGen/src/
git -C deps/CodeGen apply "$HERE/codegen.patch"
cmake -S deps/CodeGen -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release -DJITTER_INTERP=ON > /dev/null
cmake --build "$WORK/build" --target CodeGenTestSuite --parallel > "$WORK/build.log" 2>&1 || { tail -40 "$WORK/build.log"; exit 1; }
"$WORK/build/CodeGenTestSuite"
echo "Interpréteur : toute la suite de tests du générateur de code passe."
