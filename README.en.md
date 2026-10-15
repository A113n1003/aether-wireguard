# Aether

A native macOS WireGuard client built with SwiftUI and AppKit. Import your existing WireGuard configuration and manage one active tunnel from a main window or a rich menu bar popover.

[中文文档](README.md) · [Releases](https://github.com/A113n1003/aether-wireguard/releases) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

**v0.1.0 is a development prerelease.** The distributed app targets Apple Silicon and macOS 14+. It uses ad hoc signing, is not Developer ID signed or notarized, and requires external Homebrew tools. Real network end-to-end validation is still pending.

The `main` branch adds a connection service installed with one initial administrator authorization. This change is not included in v0.1.0; local installation, tunnel changes and client restart have been verified; see [validation notes](docs/validation.md). The existing release can still request a password for tunnel changes.

## Preview

Rendered from the actual SwiftUI views using `--demo` with fictional profiles and simulated traffic. These images do not demonstrate real VPN connectivity.

![Main window](docs/assets/main-window.png)

<p align="center"><img src="docs/assets/menu-bar.png" width="288" alt="Menu bar panel"> <img src="docs/assets/preferences.png" width="448" alt="Preferences"></p>

## Features

- Native main window and `NSPopover` share tunnel state, traffic and configuration selection.
- `.conf` import, raw text paste and a single-peer form. Multi-peer/advanced configurations use raw editing.
- Full configurations in local Keychain; only names, IDs and creation dates in the disk index.
- One initial administrator authorization to install the connection service; routine connect/disconnect use its restricted interface. Cancellation, switching confirmation and registered session recovery.
- Handshake timestamps, actual WireGuard counters, 60-second traffic charts and redacted diagnostics.
- Keyboard shortcuts, a compact custom close button and interface preferences. Closing the main window hides the Dock icon while keeping the menu bar app and tunnel; reopening restores the icon.

No account, subscription, application analytics or cloud configuration service. Aether is an independent community project and is not affiliated with WireGuard.

## Install

After installing [Homebrew](https://brew.sh/):

```bash
brew install bash wireguard-tools wireguard-go
```

Download the arm64 zip and `SHA256SUMS` from [Releases](https://github.com/A113n1003/aether-wireguard/releases). Verify them in the same directory:

```bash
shasum -a 256 -c SHA256SUMS
```

Extract the archive, move `Aether.app` into `/Applications`, and import a valid configuration you are authorized to use. In v0.1.0, macOS requests administrator authorization for tunnel changes.

The current app is not notarized and may be blocked by Gatekeeper. It does not provide Developer ID source authentication; review and build the source if this development distribution model does not meet your needs. Do not globally disable Gatekeeper.

## Connection service in source builds

First-time setup requires Apple Command Line Tools (`/usr/bin/python3`) and the Homebrew runtime above. Setup copies the tools and required Bash libraries into a root-owned directory and installs `io.aether.wireguard.service` as a LaunchDaemon. macOS requests administrator authorization for installation. Routine tunnel changes then use restricted NSXPC calls without repeated password requests. No administrator password is stored and no `NOPASSWD` rule is added.

The service accepts only the configured local user and exact client code-signing hash (cdhash). Updating or rebuilding the app requires another authorized setup. Disconnect any existing Aether tunnel before installation or update; other VPNs are not changed. Installation and network acceptance testing of this change remain pending.

To remove the service, first disconnect Aether, then run (adjust the app path if needed):

```bash
sudo /bin/bash /Applications/Aether.app/Contents/Resources/uninstall-helper.sh
```

User profiles are retained.

## Build and check

Requires macOS, Swift 6+, the macOS SDK and Python 3. Building and tests do not need the WireGuard runtime, request elevation or change networking.

```bash
git clone https://github.com/A113n1003/aether-wireguard.git
cd aether-wireguard
./Scripts/check.sh
./Scripts/build.sh
open dist/Aether.app
```

```bash
./Scripts/release.sh                          # arm64 zip + SHA256SUMS
dist/Aether.app/Contents/MacOS/Aether --demo   # no real tunnel or config writes
swift test                                  # full Xcode
```

Some Command Line Tools installations lack XCTest/SwiftPM frameworks. `Scripts/check.sh` provides independent assertions, including inert AppleEvent argument handling, authorization cancellation and service identity constraints, but does not claim to run XCTest. CI runs both using full Xcode.

## Current limits

One active tunnel; runtime paths fixed to `/opt/homebrew/bin`. Intel runtime support is not validated. No Kill Switch, auto-connect, per-application routing or NetworkExtension. Shell hooks and unsupported `wg-quick` extensions are rejected.

Routing is delegated to `wg-quick`. In current source builds, **Use tunnel DNS** in Preferences is off by default; system DNS is preserved unless explicitly enabled. Changes apply on the next connection and do not alter the saved configuration. When enabled, network-service DNS is delegated to `wg-quick`. Aether does not verify DNS restoration. “Tunnel established” means a handshake timestamp was observed, not continuous end-to-end reachability. Initial setup trusts the app bundle and locally installed Homebrew tools. Once installed, the service uses root-owned copies with pinned client identity. Ad hoc signing binds a particular build; it does not authenticate a Developer ID publisher. Only one local user/app version is authorized at a time.

Real handshake, IPv4/IPv6 routing, DNS restoration and long-running reconnection have not completed end-to-end acceptance testing. See the [architecture](docs/architecture.md) and [roadmap](docs/roadmap.md).

## License

Original source and icon: [MIT](LICENSE). External tools and libraries retain their upstream licenses and are not bundled in public releases. First-time setup copies the required runtime locally. See [third-party notices](THIRD_PARTY_NOTICES.md).
