# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.4] - 2026-05-22

### Fixed
- Paste into terminal now survives Sparkle auto-updates. Each CI release
  previously generated a fresh self-signed certificate, changing the app's
  designated requirement on every build. macOS TCC interprets a changed
  requirement as a different app and revokes the Accessibility grant, so
  double-click would copy text to the clipboard but never send Cmd+V.
  CI builds now import a stable certificate from a GitHub Actions secret
  so the cert-leaf hash stays identical across all releases and the grant
  persists through updates.

## [1.0.3] - 2026-05-22

### Changed
- Updates now install silently in the background instead of prompting. Sparkle
  still does its daily background check (via `SUEnableAutomaticChecks`), but
  with the new `SUAutomaticallyUpdate` flag turned on it downloads the new DMG
  without showing a dialog and swaps the bundle the next time MynahPad quits.
  The user reopens the app on the new version — no more "Install Update"
  click, no detour through the GitHub release page. EdDSA signature
  verification against `SUPublicEDKey` still runs on every download, so this
  doesn't loosen the security posture.

## [1.0.2] - 2026-05-21

### Changed
- About panel now includes a one-line tagline ("A lightweight macOS menu-bar
  app that pastes text prompts into your terminal with a double-click.")
  rendered as centered secondary text via the standard
  `NSAboutPanelOptionKey.credits` attributed-string slot, so the About window
  explains what the app does instead of showing the bare bundle name.

### Build
- Ignore `.playwright-mcp/` working directory so Playwright MCP scratch state
  no longer shows up as untracked noise in `git status`.

## [1.0.1] - 2026-05-21

### Fixed
- DMG now ships with an `/Applications` symlink next to `MynahPad.app`, so
  mounting it shows the familiar drag-to-install layout. Previously the DMG
  contained only the bundle, leaving users to figure out where to put it.

## [1.0.0] - 2026-05-21

First public release. DMG attached to this GitHub Release.

### Added
- Initial Swift/SwiftUI rewrite of MynahPad macOS menu-bar app (formerly PromptQueue)
- NSStatusItem menu bar icon with menu (Show/Hide Window, Check for Updates…, About, Quit)
- Floating, frameless dark note list window with Spotlight-style vibrancy blur
- Folder management and note CRUD operations; right-click context menus for both
- Double-click a note to paste it into the last focused app via CGEvent Cmd+V
- FocusTracker remembers the last active non-MynahPad application
- Sparkle 2.6.4 auto-updater — daily background check + "Check for Updates…" menu
  item; EdDSA signature verification of every downloaded DMG
- Drag-and-drop sorting for folders and notes via typed Transferable payloads
  (custom UTIs `com.mynahpad.folder-ref` / `com.mynahpad.note-ref`)
- JSON storage at `~/.config/mynahpad/notes.json` with auto-migration from the
  legacy `~/.config/promptqueue/notes.json` path (cross-app compatible schema)
- `build.sh` — CLT-only build (no Xcode project), downloads Sparkle on first
  build, generates a self-signed `MynahPad Dev` cert for TCC-stable rebuilds
- GitHub Actions release workflow: signs the DMG with Sparkle EdDSA, patches
  `appcast.xml` on `main`, and publishes the GitHub Release on `v*.*.*` tag push

### Changed
- Replaced the placeholder `UpdateChecker` (which only opened the GitHub
  Releases page in a browser) with **Sparkle 2.6.4** for in-app auto-updates.
  `SPUStandardUpdaterController` is wired in `AppDelegate`. A "Check for
  Updates…" menu item invokes it; a daily background check runs automatically
  via `SUScheduledCheckInterval` in Info.plist. When a newer version is found,
  Sparkle's native dialog handles download, EdDSA signature verification,
  installation, and relaunch — no browser detour, no manual DMG drag. The
  appcast URL points to `appcast.xml` at the repo root on `main`; the
  `SUPublicEDKey` for verifying releases is embedded in the bundle.
- `build.sh` downloads Sparkle 2.6.4 to `vendor/Sparkle/` on first build
  (gitignored), embeds `Sparkle.framework` in `Contents/Frameworks/`, and
  re-signs every nested Mach-O (the framework dylib, `Autoupdate`, `Updater.app`,
  and both XPC services) with the local self-signed `MynahPad Dev` cert before
  sealing the outer bundle. Hardened Runtime is deliberately off so Library
  Validation doesn't reject the framework over Team-ID mismatch (the self-signed
  cert has no Team ID).
- Renamed from **PromptQueue** to **MynahPad**. Bundle identifier
  `com.promptqueue.swift` → `com.mynahpad.app`. Signing cert
  `PromptQueue Dev` → `MynahPad Dev`. Accessibility permission must be re-granted
  once after the first build under the new identifier.
- Drag & drop overhauled with typed Transferable payloads (`FolderRef`, `NoteRef`)
  registered under custom UTIs (`com.mynahpad.folder-ref`, `com.mynahpad.note-ref`).
  Notes are sortable within a folder (drop on a note inserts before it). Folders
  are sortable (drop on a folder inserts before it). Folders cannot be dropped
  onto notes — they only reorder among folders. Visual cue is now distinct per
  drag kind: a thin accent line above the target row signals reorder/insertion,
  while a full-row accent fill on a folder signals "move note into folder".
- Window dragging fixed for drag-and-drop interactions. `isMovableByWindowBackground`
  re-enabled (so the window can be moved from any background area), with a
  `NoWindowDragRegion` (NSView wrapper exposing `mouseDownCanMoveWindow = false`)
  stamped behind note rows and folder rows so dragging a note or reordering a
  folder no longer drags the window itself.
- Used-note indicator collapsed to the green `checkmark.circle.fill` icon only;
  the redundant `"✓ "` text prefix was removed.

### Known Issues
- The DMG is signed only by the local self-signed `MynahPad Dev` cert (not an
  Apple Developer ID). On first launch macOS Gatekeeper will warn; right-click
  the app → Open → Open to bypass once. Updates after the first launch flow
  through Sparkle's signed channel and don't re-prompt.
