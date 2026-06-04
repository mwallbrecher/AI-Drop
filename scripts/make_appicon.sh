#!/usr/bin/env bash
#
# make_appicon.sh — generate the 10 macOS AppIcon PNGs from one master image.
#
# Usage:
#   scripts/make_appicon.sh [path/to/master.png]
#
# The master should be 1024×1024 (square, no rounded corners — macOS rounds it
# for you). If omitted, falls back to the existing AIDrop_Icon.png in the set.
# Output goes straight into AppIcon.appiconset/ and the Contents.json is rewritten
# with matching `filename` keys so Xcode actually uses the slots.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SET_DIR="$REPO_ROOT/MacNotchAI/Assets.xcassets/AppIcon.appiconset"
MASTER="${1:-$SET_DIR/AIDrop_Icon.png}"

if [[ ! -f "$MASTER" ]]; then
  echo "✗ master image not found: $MASTER" >&2
  exit 1
fi

W=$(sips -g pixelWidth  "$MASTER" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$MASTER" | awk '/pixelHeight/{print $2}')
echo "master: $MASTER (${W}×${H})"
if [[ "$W" -lt 1024 || "$H" -lt 1024 ]]; then
  echo "⚠️  master is smaller than 1024×1024 — the largest icon will be upscaled (soft)." >&2
fi

# slot: "<output px>  <filename>"
slots=(
  "16    icon_16x16.png"
  "32    icon_16x16@2x.png"
  "32    icon_32x32.png"
  "64    icon_32x32@2x.png"
  "128   icon_128x128.png"
  "256   icon_128x128@2x.png"
  "256   icon_256x256.png"
  "512   icon_256x256@2x.png"
  "512   icon_512x512.png"
  "1024  icon_512x512@2x.png"
)

for slot in "${slots[@]}"; do
  px="${slot%% *}"
  name="${slot##* }"
  sips -s format png -z "$px" "$px" "$MASTER" --out "$SET_DIR/$name" >/dev/null
  echo "  → $name (${px}px)"
done

cat > "$SET_DIR/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "✓ AppIcon set updated. Rebuild in Xcode to pick up the new icon."
