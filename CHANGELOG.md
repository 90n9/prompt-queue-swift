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

### Known Issues / TODO
- The release workflow uses `method: development` in ExportOptions.plist. For unsigned
  macOS archives the correct method is `mac-application`. Update once code signing
  strategy is decided (ad-hoc, Developer ID, or unsigned direct copy).
