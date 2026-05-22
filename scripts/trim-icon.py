#!/usr/bin/env python3
"""
Trim transparent margin off assets/app-icon.png and save as
assets/app-icon-trimmed.png. Used for the minimized-strip icon — the
.icns version carries the standard macOS app-icon padding which shows as
a blank frame when drawn outside the dock/Finder context.

Run after editing app-icon.png.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "app-icon.png"
OUT = ROOT / "assets" / "app-icon-trimmed.png"

img = Image.open(SRC).convert("RGBA")
bbox = img.getbbox()
if bbox is None:
    raise SystemExit(f"{SRC} appears fully transparent")
trimmed = img.crop(bbox)
trimmed.save(OUT)
print(f"trimmed {img.size} -> {trimmed.size}; wrote {OUT}")
