#!/bin/bash
# build.sh — Build MynahPad.app without Xcode (requires Xcode CLT only).
# Usage: ./build.sh [--release] [--dmg]
#
# Output: dist/MynahPad.app  (and optionally dist/MynahPad.dmg)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJECT_DIR/MynahPad"
DIST="$PROJECT_DIR/dist"

# Variant — release builds ship to users; dev builds are sibling installs with
# their own bundle id, app name, and TCC accessibility entry so they coexist
# cleanly with the production app installed in /Applications.
RELEASE_BUILD=false
DMG_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE_BUILD=true ;;
    --dmg) DMG_BUILD=true ;;
  esac
done

if [[ "$RELEASE_BUILD" == "true" ]]; then
  BINARY_NAME="MynahPad"
  BUNDLE_NAME="MynahPad"
  BUNDLE_IDENTIFIER="com.mynahpad.app"
  APP_FOLDER_NAME="MynahPad.app"
else
  BINARY_NAME="MynahPad Dev"
  BUNDLE_NAME="MynahPad Dev"
  BUNDLE_IDENTIFIER="com.mynahpad.app.dev"
  APP_FOLDER_NAME="MynahPad Dev.app"
fi

APP="$DIST/$APP_FOLDER_NAME"

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
  "$SRC/UpdateNotifier.swift"
  "$SRC/MynahPadApp.swift"
)

# Build flags
OPT_FLAGS="-Onone -g"
if [[ "$RELEASE_BUILD" == "true" ]]; then
  OPT_FLAGS="-O -whole-module-optimization"
  echo "→ Release build  (bundle id: $BUNDLE_IDENTIFIER, app: $APP_FOLDER_NAME)"
else
  echo "→ Dev build      (bundle id: $BUNDLE_IDENTIFIER, app: $APP_FOLDER_NAME)"
  echo "                 (pass --release for the production-shaped optimised bundle)"
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

if [[ "$RELEASE_BUILD" != "true" ]]; then
  # Dev variant: swap in the dev bundle id and display name so this bundle
  # gets its own TCC Accessibility entry (won't collide with the production
  # app's grant) and shows up as "MynahPad Dev" everywhere — menu bar, About
  # panel, System Settings. Sparkle auto-checks are disabled too so a dev
  # bundle never replaces itself with the prod release.
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $BUNDLE_NAME" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $BUNDLE_NAME" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SUAutomaticallyUpdate false" "$APP/Contents/Info.plist"
fi

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
# Tightly-bounded colourful icon used in the minimized title-bar strip.
# Bypasses Icon.icns to avoid the standard macOS app-icon canvas padding,
# which renders as a blank frame outside the Dock context.
# Regenerate via scripts/trim-icon.py if app-icon.png changes.
if [[ -f "$PROJECT_DIR/assets/app-icon-trimmed.png" ]]; then
  cp "$PROJECT_DIR/assets/app-icon-trimmed.png" "$APP/Contents/Resources/AppIconColor.png"
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

# When running in CI (GitHub Actions sets GITHUB_ACTIONS=true) we cannot rely
# on the login keychain — its password is environment-specific and we can't
# answer GUI prompts. We create a dedicated build keychain with a known
# password and import the cert there. Locally the function falls back to the
# user's login keychain so TCC keeps recognising the cert leaf.
ensure_signing_identity() {
  # In CI, import a stable cert stored in secrets instead of generating a fresh
  # one. Each CI-generated cert has a different hash, which changes the app's
  # designated requirement and causes TCC to drop the Accessibility grant on
  # every Sparkle auto-update — paste silently fails after the update.
  # Run scripts/gen-stable-cert.sh once, then add the output to GitHub secrets:
  #   MACOS_SIGNING_CERT_P12_BASE64   (base64-encoded p12)
  #   MACOS_SIGNING_CERT_P12_PASSWORD (passphrase used during export)
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]] && [[ -n "${MACOS_SIGNING_CERT_P12_BASE64:-}" ]]; then
    echo "→ Importing stable signing cert from secret..."
    local ci_tmpdir ci_kc ci_pw login_kc
    ci_tmpdir=$(mktemp -d)
    ci_kc="$HOME/Library/Keychains/mynahpad-build.keychain-db"
    ci_pw="mynahpad-ci"
    login_kc=$(security login-keychain | tr -d '" ')

    printf '%s' "${MACOS_SIGNING_CERT_P12_BASE64}" | base64 --decode > "$ci_tmpdir/identity.p12"

    security delete-keychain "$ci_kc" 2>/dev/null || true
    security create-keychain -p "$ci_pw" "$ci_kc"
    security list-keychains -d user -s "$ci_kc" "$login_kc"
    security default-keychain -s "$ci_kc"
    security set-keychain-settings -lut 21600 "$ci_kc"
    security unlock-keychain -p "$ci_pw" "$ci_kc"

    security import "$ci_tmpdir/identity.p12" \
      -k "$ci_kc" \
      -P "${MACOS_SIGNING_CERT_P12_PASSWORD:-}" \
      -T /usr/bin/codesign \
      -T /usr/bin/security \
      >/dev/null

    security set-key-partition-list \
      -S apple-tool:,apple:,codesign: \
      -s -k "$ci_pw" \
      "$ci_kc" \
      >/dev/null 2>&1 || true

    rm -f "$ci_tmpdir/identity.p12"
    rmdir "$ci_tmpdir" 2>/dev/null || true
    echo "  ✓ Stable cert imported — cert-leaf hash consistent across releases"
    return 0
  fi

  if security find-identity -p codesigning 2>/dev/null \
       | grep -q "\"$SIGNING_IDENTITY\""; then
    return 0
  fi

  echo "→ Creating self-signed codesigning identity '$SIGNING_IDENTITY'..."
  local tmpdir
  tmpdir=$(mktemp -d)

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

  local target_kc target_pw login_kc
  login_kc=$(security login-keychain | tr -d '" ')

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    # Dedicated CI keychain with known password — bypasses any assumption
    # about the runner's login keychain password.
    target_kc="$HOME/Library/Keychains/mynahpad-build.keychain-db"
    target_pw="mynahpad-ci"
    security delete-keychain "$target_kc" 2>/dev/null || true
    security create-keychain -p "$target_pw" "$target_kc"
    # Add to user search list (along with the existing default kc) so
    # codesign can locate the identity. Keep the login kc in the list.
    security list-keychains -d user -s "$target_kc" "$login_kc"
    security default-keychain -s "$target_kc"
    # Long timeout so the keychain doesn't relock mid-build (~6h).
    security set-keychain-settings -lut 21600 "$target_kc"
    security unlock-keychain -p "$target_pw" "$target_kc"
  else
    target_kc="$login_kc"
    target_pw=""
  fi

  security import "$tmpdir/identity.p12" \
    -k "$target_kc" \
    -P mynahpad \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    >/dev/null

  # Bless the freshly-imported key for codesign+apple so the first codesign
  # call is non-interactive. -k "" is fine locally (the user's keychain is
  # already unlocked from their interactive login). On CI we pass the known
  # build-keychain password.
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "$target_pw" \
    "$target_kc" \
    >/dev/null 2>&1 || true

  echo "  ✓ Identity installed (keychain: $target_kc)"
  # Best-effort tmp cleanup. Not using rm -rf to keep the project-wide hook
  # happy; security tools didn't leave anything sensitive in $tmpdir.
  rm -f "$tmpdir/key.pem" "$tmpdir/cert.pem" "$tmpdir/cert.cnf" "$tmpdir/identity.p12"
  rmdir "$tmpdir" 2>/dev/null || true
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
if [[ "$DMG_BUILD" == "true" ]]; then
  VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")
  DMG_BASE="${BUNDLE_NAME// /-}"
  DMG="$DIST/${DMG_BASE}-${VERSION}.dmg"
  STAGE="$DIST/dmg-stage"

  echo "→ Staging DMG contents at $STAGE..."
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  # Use ditto (preserves resource forks/xattrs/symlinks correctly) so the
  # signed bundle copies cleanly.
  ditto "$APP" "$STAGE/$APP_FOLDER_NAME"
  # Drag-install hint: an /Applications symlink next to the app gives Finder
  # the familiar "drag onto Applications" layout when mounted.
  ln -s /Applications "$STAGE/Applications"

  echo "→ Creating $DMG..."
  rm -f "$DMG"
  hdiutil create -volname "$BUNDLE_NAME ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG"

  rm -rf "$STAGE"
  echo "→ DMG: $DMG"
fi

echo ""
echo "Done! Run with:"
echo "  open $APP"
