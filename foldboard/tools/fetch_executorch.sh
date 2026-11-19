#!/bin/bash
# Récupère les binaires iOS d'ExecuTorch 1.6.0 (ceux de la sonde du 18 novembre).
# Ils ne sont pas dans git : trop gros, et régénérés à chaque build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor"
mkdir -p "$DEST"
BASE="https://ossci-ios.s3.amazonaws.com/executorch"
V=1.6.0
cd "$DEST"
for name in executorch backend_xnnpack kernels_optimized kleidiai threadpool; do
  if [ ! -d "$name.xcframework/ios-arm64" ]; then
    echo "fetch $name $V"
    curl -fsSL -o "$name.zip" "$BASE/${name}-${V}.zip"
    rm -rf "$name.xcframework"
    unzip -q -o "$name.zip"
    rm -f "$name.zip"
  fi
done
echo "ExecuTorch $V prêt dans $DEST"
