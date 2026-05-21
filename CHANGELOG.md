# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial Swift/SwiftUI rewrite of MynahPad macOS menu-bar app (formerly PromptQueue)
- NSStatusItem menu bar icon with update check support
- Floating, frameless dark note list window
- Folder management and note CRUD operations
- Double-click to paste note into last focused app via CGEvent Cmd+V
- FocusTracker to remember the last active non-MynahPad application
- UpdateChecker fetching latest release from GitHub API
- JSON storage at `~/.config/mynahpad/notes.json` with auto-migration from the
  legacy `~/.config/promptqueue/notes.json` path (cross-app compatible schema)
- GitHub Actions release workflow building unsigned .app DMG on `v*.*.*` tags

### Changed
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

### Known Issues / TODO
- The release workflow uses `method: development` in ExportOptions.plist. For unsigned
  macOS archives the correct method is `mac-application`. Update once code signing
  strategy is decided (ad-hoc, Developer ID, or unsigned direct copy).
