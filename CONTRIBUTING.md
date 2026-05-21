# Contributing to MynahPad

## Build from source

### Prerequisites

- **macOS 13 Ventura or later** (uses `.draggable` / `.dropDestination`)
- **Xcode Command Line Tools** — `xcode-select --install`. Full Xcode is not
  required; `build.sh` produces a `.app` bundle using `swiftc` and `codesign`
  from the CLT only.

### Build

`build.sh` is the only supported build path — there is no `.xcodeproj`.

```bash
git clone git@github.com:90n9/mynah-pad.git
cd mynah-pad
./build.sh                   # Debug → dist/MynahPad.app
./build.sh --release         # Optimised
./build.sh --release --dmg   # Also wrap in a DMG
```

The first build downloads Sparkle (~13 MB) to `vendor/Sparkle/` (gitignored).
It also generates a self-signed code-signing certificate named **MynahPad Dev**
in your login keychain — required so the TCC Accessibility grant survives
rebuilds (see below). Subsequent builds reuse the cert silently.

## Why the self-signed cert

macOS TCC (the privacy database that gates Accessibility) matches grants
against the binary's **designated requirement**, not its bundle ID alone.
With ad-hoc signing (`codesign --sign -`) the designated requirement is
literally `cdhash H"<binary hash>"`, which changes every rebuild — so TCC
silently invalidates the previous grant and `CGEventPost` no-ops until you
re-toggle Accessibility in System Settings.

Signing with a stable certificate makes the designated requirement
`identifier "com.mynahpad.app" and certificate leaf = H"<cert hash>"`. The
cert hash never changes between rebuilds, so the TCC grant persists. The cert
is self-signed (it shows up as `CSSMERR_TP_NOT_TRUSTED` in
`security find-identity -v` — that's expected; TCC matches by leaf-cert hash,
not trust-chain validity).

If paste ever silently fails after a rebuild:

```bash
codesign -d -r- dist/MynahPad.app
# designated => identifier "com.mynahpad.app" and certificate leaf = H"..."
#                                              ^ must be `certificate leaf`,
#                                                not `cdhash`
```

If the line shows `cdhash` instead, the cert bootstrap failed — delete `dist/`,
re-run `./build.sh`, and check its output for the cert-creation step.

## Auto-update (Sparkle)

MynahPad uses **[Sparkle](https://sparkle-project.org/)** for in-app updates.
On launch it polls [`appcast.xml`](appcast.xml) at the repo root; a daily
background check is scheduled via `SUScheduledCheckInterval`. With
`SUAutomaticallyUpdate=true` in `Info.plist`, downloads happen silently and
Sparkle installs them on the app's next quit — no native dialog. Every
download is EdDSA-verified against `SUPublicEDKey` in `Info.plist` before
install, so silent updates don't loosen the security posture.

The Sparkle framework is downloaded by `build.sh` to `vendor/Sparkle/`
(gitignored) on first build, embedded in `Contents/Frameworks/`, and
re-signed with the local `MynahPad Dev` cert so it loads under the same
identity as the host binary.

## Cutting a release

Releases are fully automated by GitHub Actions. Maintainer steps:

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in
   `MynahPad/Info.plist`.
2. Move the `## [Unreleased]` section in `CHANGELOG.md` under a new version
   heading.
3. Commit and push to `main`.
4. Tag and push: `git tag v1.2.3 && git push --tags`.

The release workflow then builds the DMG, signs it with the Sparkle EdDSA key,
commits the updated `appcast.xml` back to `main`, and publishes the GitHub
Release. Existing installs pick up the new version on their next appcast
check (within ~24 h via the daily background poll).

## Sparkle signing key

The Sparkle EdDSA private key is **already provisioned** — do not regenerate
it. Running `generate_keys` again would mint a new key and invalidate the
signature on every prior release, so Sparkle on existing installs would
reject the update.

The key lives in three places:

- The maintainer's **macOS Keychain** (canonical — created by `generate_keys`).
- `~/.sparkle/mynah-pad-ed-key.pem` (local backup, kept out of the repo).
- The `SPARKLE_ED_PRIVATE_KEY` **GitHub Actions secret** (used by the release
  workflow to sign DMGs in CI).

The matching public key is embedded in the app as `SUPublicEDKey` in
`MynahPad/Info.plist` and is used by Sparkle to verify downloaded updates.
