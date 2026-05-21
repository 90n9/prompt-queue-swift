<p align="center">
  <img src="assets/app-icon.png" alt="MynahPad" width="180" height="180" />
</p>

<h1 align="center">MynahPad <sub><sup>(Swift)</sup></sub></h1>

<p align="center">
  A lightweight macOS menu-bar app that manages a list of text prompts and pastes
  them into your active terminal with a double-click. Targets a ~2 MB binary —
  the Python/PyQt6 predecessor produced a ~200 MB DMG.
</p>

## Prerequisites

- **macOS 13 Ventura or later** (uses `.draggable` / `.dropDestination`)
- **Xcode Command Line Tools** — `xcode-select --install`. Full Xcode is not required;
  `build.sh` produces a `.app` bundle using `swiftc` from the CLT only.

## Build

```bash
git clone git@github.com:90n9/mynah-pad.git
cd mynah-pad
./build.sh                   # Debug build → dist/MynahPad.app
./build.sh --release         # Optimised build
./build.sh --release --dmg   # Also wrap in a DMG
```

On the first run, `build.sh` generates a self-signed code-signing certificate named
**MynahPad Dev** and installs it in your login keychain (see *Accessibility* below
for why). Subsequent builds reuse the same cert — no prompts.

## Accessibility Permission

MynahPad needs **Accessibility access** to simulate Cmd+V and paste prompts into your
terminal. On first run (or when the Accessibility permission is missing) macOS will
prompt you. You can also grant it manually:

**System Settings → Privacy & Security → Accessibility → enable MynahPad**

Without this permission the paste feature silently does nothing.

### Why the self-signed cert

macOS TCC (the privacy database that gates Accessibility) matches grants against the
binary's **designated requirement**, not its bundle ID alone. With **ad-hoc** signing
(`codesign --sign -`) the designated requirement is literally `cdhash H"<binary hash>"` —
which changes every time you rebuild, so TCC silently invalidates the previous grant and
`CGEventPost` no-ops until you re-toggle Accessibility in System Settings.

Signing with a stable certificate makes the designated requirement
`identifier "com.mynahpad.app" and certificate leaf = H"<cert hash>"`. The cert
hash never changes between rebuilds, so the TCC grant persists. The cert is self-signed
(it shows up as `CSSMERR_TP_NOT_TRUSTED` in `security find-identity -v` — that's
expected; TCC matches by leaf-cert hash, not trust-chain validity).

If paste ever silently fails after a rebuild:

```bash
codesign -d -r- dist/MynahPad.app
# designated => identifier "com.mynahpad.app" and certificate leaf = H"..."
#                                              ^ must be `certificate leaf`,
#                                                not `cdhash`
```

If the line shows `cdhash` instead of `certificate leaf`, the cert bootstrap failed —
delete `dist/`, re-run `./build.sh`, and check its output for the cert-creation step.

## Storage

Notes are stored at `~/.config/mynahpad/notes.json`. On first launch, MynahPad
auto-migrates from the legacy `~/.config/promptqueue/notes.json` location if it
exists. The schema is compatible with the Python predecessor, so you can also seed
the file manually.

## Usage

1. Launch MynahPad — a `📝` icon appears in the menu bar.
2. Click the icon → **Show Window** to open the note list.
3. Type a prompt in the **New idea…** field and press Return to add it.
4. Switch to your terminal, then **double-click** a note to paste it.
5. Used notes turn grey with a ✓ prefix. Right-click for Reset / Delete / Move to folder.

## Release

Tag with `v<MAJOR>.<MINOR>.<PATCH>` to trigger the GitHub Actions release workflow,
which builds an unsigned DMG and attaches it to a GitHub release.

## License

MIT
