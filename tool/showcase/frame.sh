#!/usr/bin/env bash
# Puts each raw screen on the brand gradient under a caption, as a store
# screenshot: 1242 × 2688, 24-bit PNG with no alpha.
#
#   tool/showcase/frame.sh RAW_DIR OUT_DIR
set -euo pipefail
RAW=$1
OUT=$2
mkdir -p "$OUT"
FONT=${SHOWCASE_CAPTION_FONT:-/usr/share/fonts/rsms-inter-fonts/Inter-ExtraBold.ttf}
W=1242
H=2688
SCREEN_W=1010
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

caption() {
  case "$1" in
    01_home) echo "Real Japanese, picked for your level" ;;
    02_dialogue) echo "Tap any word to see its meaning" ;;
    03_flashcards) echo "Review the words you saved" ;;
    04_companion) echo "Grow a companion as you learn" ;;
    05_library) echo "Videos, books and dialogues in one place" ;;
    06_profile) echo "Keep your streak going" ;;
    *) echo "" ;;
  esac
}

magick -size "${H}x${W}" gradient:'#5094F7'-'#2F6FED' -rotate 90 \
  -fill 'rgba(255,255,255,0.07)' \
  -draw "circle 1100,300 1100,0" -draw "circle 120,2500 120,2150" \
  "$TMP/bg.png"

for raw in "$RAW"/*.png; do
  name=$(basename "$raw" .png)
  # The screen with rounded corners and a soft shadow.
  magick "$raw" -resize "${SCREEN_W}x" "$TMP/screen.png"
  read -r sw sh < <(magick identify -format "%w %h\n" "$TMP/screen.png")
  magick -size "${sw}x${sh}" xc:none -fill white \
    -draw "roundrectangle 0,0,$((sw - 1)),$((sh - 1)),56,56" "$TMP/mask.png"
  magick "$TMP/screen.png" "$TMP/mask.png" -alpha off -compose CopyOpacity \
    -composite "$TMP/rounded.png"
  magick "$TMP/rounded.png" \( +clone -background '#0B2A6B' -shadow 45x28+0+18 \) \
    +swap -background none -layers merge +repage "$TMP/shadowed.png"
  # The caption, wrapped to two lines at most.
  magick -background none -fill white -font "$FONT" -size 1060x300 \
    -gravity center caption:"$(caption "$name")" "$TMP/caption.png"
  magick "$TMP/bg.png" \
    "$TMP/caption.png" -gravity north -geometry +0+70 -composite \
    "$TMP/shadowed.png" -gravity north -geometry +0+400 -composite \
    -alpha off -define png:color-type=2 "PNG24:$OUT/$name.png"
done
