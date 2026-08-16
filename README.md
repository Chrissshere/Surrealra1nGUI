# surrealra1n GUI

surrealra1n GUI is a native macOS front end for [surrealra1n](https://github.com/pwnerblu/surrealra1n). It follows the same restore flow as the shell script, but presents device detection, firmware selection, DFU instructions, progress, and logs in a small AppKit wizard.

This is beta software. A restore can erase the connected device, and tethered installations need Just Boot after every shutdown. Keep a backup and read the log before retrying a failed restore.

## Requirements

- macOS 12 or later
- An Intel or Apple Silicon Mac
- Xcode 27 to build the checked-in project
- A surrealra1n-supported device
- Internet access while the app starts

Virtual machines are not supported. The app will not work inside a VM. The iPhone must be connected directly to the physical Mac because the USB connection and DFU handoffs need direct access to the device.

The release is universal and contains native `x86_64` and `arm64` code. Mojave is not advertised because the current Xcode toolchain cannot produce or verify a macOS 10.14 build.

## How it works

The app downloads a fresh copy of the surrealra1n development branch for each session. The archive is unpacked in a temporary directory and removed when the app quits. The downloaded repository is left untouched; the GUI runs a temporary copy of the script with the selected IPSW, SHSH, and boot version supplied through environment variables.

Restore output is shown live on the progress screen and in a separate log window. Generated restore files and bootchains are kept in Application Support, so they survive between sessions. The bootchain location can be changed from Options, and an existing bootchain folder can be imported from the Just Boot screen.

SHSH restore is disabled for A12 and A13 devices. The GUI follows the same limitation as the underlying script rather than offering an option that cannot work.

## Building

Open `Surrealra1nGUI.xcodeproj`, choose the `Surrealra1nGUI` scheme, and build the Release configuration. The project does not use third-party Swift packages.

For a command-line build:

```bash
xcodebuild \
  -project Surrealra1nGUI.xcodeproj \
  -scheme Surrealra1nGUI \
  -configuration Release \
  -derivedDataPath build \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

To create the universal DMG and PKG used for a release:

```bash
./scripts/package-release.sh 0.0.2-beta
```

## Demo mode

The fake-device workflow is kept out of the normal interface. Developers can expose it locally with:

```bash
defaults write com.surrealra1n.gui EnableDemoMode -bool true
```

Remove the preference to hide it again:

```bash
defaults delete com.surrealra1n.gui EnableDemoMode
```

## Credits

GUI by chrissyx. surrealra1n is maintained by pwnerblu.

Thanks to iSuns9, bodyc1m, Mineek, Remedgit, BatuBey5G, the checkra1n team, and the usbliter8 developers.

## Coming soon lol

iOS 17, iOS 18, and iOS 26 experiments, a jailbreak utility for supported downgraded systems, and Cryptex-ticket research are planned work. They are not implemented in this release.
