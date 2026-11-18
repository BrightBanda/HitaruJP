#!/usr/bin/env bash
# Renders store screenshots of the real app screens with mock data.
#
#   tool/showcase/run.sh
#
# Downloads (once) a few free stock photos (Lorem Picsum, Unsplash-licensed)
# into build/showcase/cache for video thumbnails, renders
# tool/showcase/showcase_test.dart into build/showcase/raw, then frames each
# screen with a caption into branding/store/apkpure/screenshots (24-bit PNG,
# no alpha). Nothing here is part of the app or its normal test run.
#
# Needs ImageMagick, the Inter font and Noto Sans CJK JP.
set -euo pipefail
cd "$(dirname "$0")/../.."
CACHE=build/showcase/cache
RAW=build/showcase/raw
OUT=branding/store/apkpure/screenshots
mkdir -p "$CACHE/photos" "$RAW" "$OUT"

for id in 164 225 292 431 1043 1047 1060 1067; do
  [[ -s "$CACHE/photos/p$id.jpg" ]] ||
    curl -sfL -o "$CACHE/photos/p$id.jpg" "https://picsum.photos/id/$id/960/540"
done

FLUTTER_ROOT_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
SHOWCASE_CACHE="$PWD/$CACHE" \
SHOWCASE_OUT="$PWD/$RAW" \
SHOWCASE_FONTS="$FLUTTER_ROOT_DIR/bin/cache/artifacts/material_fonts" \
SHOWCASE_CJK="${SHOWCASE_CJK:-/usr/share/fonts/google-noto-sans-cjk-vf-fonts/NotoSansCJK-VF.ttc}" \
  flutter test tool/showcase/showcase_test.dart "$@"

bash tool/showcase/frame.sh "$RAW" "$OUT"
echo "==> Screenshots in $OUT"
