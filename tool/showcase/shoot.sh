#!/usr/bin/env bash
# Renders the raw screens only (no photo download, no framing), for quick
# iteration: tool/showcase/shoot.sh [--plain-name NAME]
set -euo pipefail
cd "$(dirname "$0")/../.."
FLUTTER_ROOT_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
SHOWCASE_CACHE="$PWD/build/showcase/cache" \
SHOWCASE_OUT="$PWD/build/showcase/raw" \
SHOWCASE_FONTS="$FLUTTER_ROOT_DIR/bin/cache/artifacts/material_fonts" \
SHOWCASE_CJK="${SHOWCASE_CJK:-/usr/share/fonts/google-noto-sans-cjk-vf-fonts/NotoSansCJK-VF.ttc}" \
  flutter test tool/showcase/showcase_test.dart "$@"
