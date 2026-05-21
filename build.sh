#!/bin/bash
# build.sh — Build MynahPad.app without Xcode (requires Xcode CLT only).
# Usage: ./build.sh [--release] [--dmg]
#
# Output: dist/MynahPad.app  (and optionally dist/MynahPad.dmg)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJECT_DIR/MynahPad"
DIST="$PROJECT_DIR/dist"
APP="$DIST/MynahPad.app"
BINARY_NAME="MynahPad"

SPARKLE_VERSION="2.6.4"
SPARKLE_DIR="$PROJECT_DIR/vendor/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_DIR/Sparkle.framework"

ensure_sparkle() {
  if [[ -d "$SPARKLE_FRAMEWORK" ]]; then return 0; fi
  echo "→ Downloading Sparkle $SPARKLE_VERSION..."
  mkdir -p "$PROJECT_DIR/vendor"
  local tarball="$PROJECT_DIR/vendor/Sparkle-$SPARKLE_VERSION.tar.xz"
  curl -L -s -o "$tarball" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  mkdir -p "$SPARKLE_DIR"
  tar -xJf "$tarball" -C "$SPARKLE_DIR"
  rm "$tarball"
}

ensure_sparkle

SDK="$(xcrun --show-sdk-path)"
SOURCES=(
  "$SRC/Models/Folder.swift"
  "$SRC/Models/Note.swift"
  "$SRC/Models/Store.swift"
  "$SRC/Services/FocusTracker.swift"
  "$SRC/Services/Paster.swift"
  "$SRC/AppDelegate.swift"
  "$SRC/StatusBarController.swift"
  "$SRC/NoteListWindow.swift"
  "$SRC/NoteListView.swift"
  "$SRC/MynahPadApp.swift"
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
mkdir -p "$DIST"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -swift-version 5 \
  $OPT_FLAGS \
  -F "$SPARKLE_DIR" \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreGraphics \
  -framework Foundation \
  -framework Sparkle \
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
  "${SOURCES[@]}" \
  -o "$DIST/$BINARY_NAME"

echo "→ Assembling .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"

cp "$DIST/$BINARY_NAME" "$APP/Contents/MacOS/$BINARY_NAME"
rm "$DIST/$BINARY_NAME"

# Embed Sparkle.framework. The framework brings nested XPC services
# (Downloader.xpc, Installer.xpc, Updater.xpc) — preserve them with -R.
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

# Fix Info.plist: replace the Xcode build variable with the real executable name.
sed "s/\$(EXECUTABLE_NAME)/$BINARY_NAME/g" \
  "$SRC/Info.plist" > "$APP/Contents/Info.plist"

# Copy PkgInfo (required by macOS app loader)
printf "APPL????" > "$APP/Contents/PkgInfo"

# Bundle icons. Icon.icns must be regenerated via scripts/generate-icon.sh
# whenever assets/app-icon.png changes — it's not rebuilt automatically here
# so the build stays a single swiftc invocation.
if [[ -f "$PROJECT_DIR/assets/Icon.icns" ]]; then
  cp "$PROJECT_DIR/assets/Icon.icns" "$APP/Contents/Resources/Icon.icns"
else
  echo "  ⚠ assets/Icon.icns missing — run scripts/generate-icon.sh"
fi
if [[ -f "$PROJECT_DIR/assets/mini-icon.png" ]]; then
  cp "$PROJECT_DIR/assets/mini-icon.png" "$APP/Contents/Resources/MiniIcon.png"
fi

echo "→ Built: $APP"
ls -lh "$APP/Contents/MacOS/$BINARY_NAME"

# Remove Gatekeeper quarantine so it runs without the unsigned-app block.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Codesign with a self-signed cert so the TCC Accessibility grant survives
# rebuilds. Ad-hoc signing isn't enough: an ad-hoc binary's designated
# requirement is literally `cdhash H"<hash>"`, which changes every time the
# source changes, so TCC drops the grant on every rebuild. A self-signed
# cert gives a DR of the form `identifier "com.mynahpad.app" and
# certificate leaf = H"<stable cert hash>"` — stable across rebuilds, so
# the grant sticks.
SIGNING_IDENTITY="MynahPad Dev"

ensure_signing_identity() {
  # Don't use -v here: self-signed certs are flagged CSSMERR_TP_NOT_TRUSTED,
  # which `-v` filters out, but they're still usable for codesigning and TCC
  # matching (which compares the leaf cert hash, not trust-chain validity).
  if security find-identity -p codesigning 2>/dev/null \
       | grep -q "\"$SIGNING_IDENTITY\""; then
    return 0
  fi

  echo "→ Creating self-signed codesigning identity '$SIGNING_IDENTITY'..."
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  cat > "$tmpdir/cert.cnf" <<EOF
[req]
distinguished_name = req_dn
prompt = no

[req_dn]
CN = $SIGNING_IDENTITY

[v3_codesign]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOF

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$tmpdir/key.pem" \
    -out "$tmpdir/cert.pem" \
    -days 3650 \
    -config "$tmpdir/cert.cnf" \
    -extensions v3_codesign 2>/dev/null

  # OpenSSL 3 defaults to AES-256/SHA-256 PBE which macOS Security framework
  # can't import. Force legacy SHA-1 / 3DES PBE so `security import` works.
  openssl pkcs12 -export \
    -inkey "$tmpdir/key.pem" \
    -in "$tmpdir/cert.pem" \
    -name "$SIGNING_IDENTITY" \
    -out "$tmpdir/identity.p12" \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg SHA1 \
    -passout pass:mynahpad

  local login_kc
  login_kc=$(security login-keychain | tr -d '" ')

  # -T /usr/bin/codesign lets codesign use the key without a per-build
  # password prompt.
  security import "$tmpdir/identity.p12" \
    -k "$login_kc" \
    -P mynahpad \
    -T /usr/bin/codesign \
    >/dev/null

  echo "  ✓ Identity installed in login keychain"
  echo "  ⚠ First codesign call may show 'Always Allow' prompt — click it once."
}

ensure_signing_identity

echo "→ Codesigning with '$SIGNING_IDENTITY'..."

# Sign Sparkle inside-out, then the outer app. Order matters: the outer
# bundle seals everything beneath it, so children must be signed first.
#
# No `--options runtime` here: Hardened Runtime enforces Library Validation,
# which requires every loaded framework to share a Team ID with the host.
# Self-signed certs have no Team ID, so loading would fail. For dev builds
# this is fine — notarization needs runtime, dev builds don't.
SPARKLE_FW_IN_APP="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_INNER="$SPARKLE_FW_IN_APP/Versions/B"

# Innermost binaries and helpers
for path in \
    "$SPARKLE_INNER/Sparkle" \
    "$SPARKLE_INNER/Autoupdate" \
    "$SPARKLE_INNER/Updater.app" \
    "$SPARKLE_INNER/XPCServices/Downloader.xpc" \
    "$SPARKLE_INNER/XPCServices/Installer.xpc"
do
  if [[ -e "$path" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" "$path" 2>&1 | sed 's/^/  /'
  fi
done

# Framework bundle itself
codesign --force --sign "$SIGNING_IDENTITY" "$SPARKLE_FW_IN_APP" 2>&1 | sed 's/^/  /'

# Outer app bundle (seals everything above).
codesign --force --sign "$SIGNING_IDENTITY" "$APP" 2>&1 | sed 's/^/  /'

# Show the designated requirement so you can confirm it's cert-based, not cdhash-based.
echo "→ Designated requirement:"
codesign -d -r- "$APP" 2>&1 | grep -i "designated" | sed 's/^/  /' || true

# Optional: wrap in a DMG.
if [[ "${1:-}" == "--dmg" ]] || [[ "${2:-}" == "--dmg" ]]; then
  VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")
  DMG="$DIST/MynahPad-${VERSION}.dmg"
  echo "→ Creating $DMG..."
  hdiutil create -volname MynahPad \
    -srcfolder "$APP" \
    -ov -format UDZO \
    "$DMG"
  echo "→ DMG: $DMG"
fi

echo ""
echo "Done! Run with:"
echo "  open $APP"
