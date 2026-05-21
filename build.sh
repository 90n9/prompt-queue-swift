#!/bin/bash
# build.sh — Build PromptQueue.app without Xcode (requires Xcode CLT only).
# Usage: ./build.sh [--release] [--dmg]
#
# Output: dist/PromptQueue.app  (and optionally dist/PromptQueue.dmg)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJECT_DIR/PromptQueue"
DIST="$PROJECT_DIR/dist"
APP="$DIST/PromptQueue.app"
BINARY_NAME="PromptQueue"

SDK="$(xcrun --show-sdk-path)"
SOURCES=(
  "$SRC/Models/Folder.swift"
  "$SRC/Models/Note.swift"
  "$SRC/Models/Store.swift"
  "$SRC/Services/FocusTracker.swift"
  "$SRC/Services/Paster.swift"
  "$SRC/Services/UpdateChecker.swift"
  "$SRC/AppDelegate.swift"
  "$SRC/StatusBarController.swift"
  "$SRC/NoteListWindow.swift"
  "$SRC/NoteListView.swift"
  "$SRC/PromptQueueApp.swift"
)

# Build flags
OPT_FLAGS="-Onone -g"
if [[ "${1:-}" == "--release" ]] || [[ "${2:-}" == "--release" ]]; then
  OPT_FLAGS="-O -whole-module-optimization"
  echo "→ Release build"
else
  echo "→ Debug build (pass --release for optimised build)"
fi

echo "→ Compiling Swift sources..."
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx12.0 \
  -swift-version 5 \
  $OPT_FLAGS \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreGraphics \
  -framework Foundation \
  "${SOURCES[@]}" \
  -o "$DIST/$BINARY_NAME"

echo "→ Assembling .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$DIST/$BINARY_NAME" "$APP/Contents/MacOS/$BINARY_NAME"
rm "$DIST/$BINARY_NAME"

# Fix Info.plist: replace the Xcode build variable with the real executable name.
sed "s/\$(EXECUTABLE_NAME)/$BINARY_NAME/g" \
  "$SRC/Info.plist" > "$APP/Contents/Info.plist"

# Copy PkgInfo (required by macOS app loader)
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "→ Built: $APP"
ls -lh "$APP/Contents/MacOS/$BINARY_NAME"

# Remove Gatekeeper quarantine so it runs without the unsigned-app block.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Optional: wrap in a DMG.
if [[ "${1:-}" == "--dmg" ]] || [[ "${2:-}" == "--dmg" ]]; then
  VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")
  DMG="$DIST/PromptQueue-${VERSION}.dmg"
  echo "→ Creating $DMG..."
  hdiutil create -volname PromptQueue \
    -srcfolder "$APP" \
    -ov -format UDZO \
    "$DMG"
  echo "→ DMG: $DMG"
fi

echo ""
echo "Done! Run with:"
echo "  open $APP"
