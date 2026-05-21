#!/bin/bash
# Regenerate assets/Icon.icns from assets/app-icon.png.
# Re-run after editing the source PNG.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS="$ROOT/assets"
SOURCE="$ASSETS/app-icon.png"
ICONSET="$ASSETS/AppIcon.iconset"
OUTPUT="$ASSETS/Icon.icns"

if [[ ! -f "$SOURCE" ]]; then
  echo "error: $SOURCE not found" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT
SQUARE="$TMP/square-1024.png"

# Pad to a square canvas, then resize to 1024 (sips can't pad with alpha — use Python/PIL).
python3 - <<PY
from PIL import Image
src = Image.open("$SOURCE").convert("RGBA")
side = max(src.size)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.paste(src, ((side - src.size[0]) // 2, (side - src.size[1]) // 2), src)
canvas = canvas.resize((1024, 1024), Image.LANCZOS)
canvas.save("$SQUARE", "PNG", optimize=True)
PY

# Build the .iconset with every macOS-required resolution.
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SQUARE" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  t=$((s * 2))
  sips -z $t $t "$SQUARE" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"

echo "→ $(du -h "$OUTPUT" | cut -f1)  $OUTPUT"
