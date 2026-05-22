# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.10] - 2026-05-22

### Fixed
- "Restart now" no longer relaunches into the same version. The previous
  build hooked Sparkle's `didDownloadUpdate` callback and immediately
  prompted to restart, but at that point Sparkle has only finished
  downloading — it hasn't yet extracted, validated, or staged the new
  bundle. Quitting that early skipped the installer entirely and reopened
  the running build. We now defer to Sparkle's standard user driver,
  which shows its own "Install Update and Relaunch" prompt once the
  package is actually staged — the popup that already worked correctly
  when the user picked "Later" on the old prompt.
- Sparkle release-notes pane in the update dialog now shows the actual
  CHANGELOG entry instead of the empty `[Unreleased]` placeholder. The
  workflow's appcast-description extractor was matching any `## [...]`
  heading first, so an empty `[Unreleased]` section above the real
  version heading clobbered the description. Tightened the regex to
  require a digit (matching the GitHub Release body extractor that was
  already doing it correctly).

## [1.0.9] - 2026-05-22

### Added
- The note panel now opens automatically on app launch instead of waiting for
  the user to click the menu-bar icon — so the first thing you see after
  starting MynahPad is your notes.
- In-panel update banner. When Sparkle's background check finds a newer
  version, an accent-colored banner appears at the top of the panel with
  the new version number and an `Update Now` button that re-presents the
  native install dialog (handy after dismissing the popup with "Later"). A
  small `×` dismisses the banner without affecting Sparkle's state.

### Changed
- `build.sh` now produces a clearly-separated "MynahPad Dev" bundle by
  default. The dev variant uses bundle id `com.mynahpad.app.dev`, app name
  `MynahPad Dev`, and writes notes under `~/.config/mynahpad-dev/notes.json`,
  so it never collides with the production app's TCC Accessibility grant or
  data store. Pass `--release` to build the production-shaped bundle. Dev
  bundles also have Sparkle auto-checks disabled so a local build never
  silently swaps itself out for the production release.

## [1.0.8] - 2026-05-22

### Fixed
- Accessibility permission dialog no longer re-fires on every launch when the
  grant is genuinely in place. The launch-time check now uses the side-effect-
  free `AXIsProcessTrusted()` first; only if untrusted do we present our own
  alert. The alert offers an `Open System Settings` action and a `Reset & Grant`
  action that runs `tccutil reset Accessibility com.mynahpad.app` — useful when
  a stale TCC grant from a different code signature is blocking paste.

### Changed
- Version strings now match between the status bar menu and Sparkle's
  "Check for Updates…" dialog (both render `MynahPad 1.0.8`). `CFBundleVersion`
  is kept in lockstep with `CFBundleShortVersionString` so Sparkle no longer
  appends a `(build)` suffix.
- Scheduled update check interval reduced from 24h to 1h while the app is
  early-stage and shipping frequent fixes.

## [1.0.7] - 2026-05-22

### Fixed
- Folder drag-to-reorder now works correctly. Folder rows were wrapped in
  `Button(action:)` whose gesture recognizer consumed touches before SwiftUI's
  drag recognizer could start, making folders un-draggable while note rows
  (which used `.onTapGesture`) dragged fine. Converted both sidebar and stacked
  folder row builders to use `.onTapGesture` instead of `Button`, matching the
  note row pattern.

## [1.0.6] - 2026-05-22

### Added
- "View on GitHub" menu item in the status bar menu opens the project repository
  in the default browser.

## [1.0.5] - 2026-05-22

### Fixed
- Auto-updates now actually install on relaunch. `SUEnableInstallerLauncherService`
  was set to `false`, which disabled the Sparkle service responsible for swapping
  the bundle when the app quits. With it re-enabled Sparkle can replace the running
  version and relaunch into the new one automatically.

### Added
- "Restart Now" alert appears when Sparkle finishes downloading an update in the
  background, so you can apply it immediately instead of waiting for next launch.

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
