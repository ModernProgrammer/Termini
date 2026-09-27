<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/images/Termini%20Dark.png" width="150">
  <source media="(prefers-color-scheme: light)" srcset="assets/images/Termini%20Light.png" width="150">
  <img alt="Project Logo" src="assets/images/Termini%20DColor.png" width="150">
</picture>

![GitHub release (latest by date)](https://img.shields.io/github/v/release/ModernProgrammer/Termini)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/github/license/ModernProgrammer/Termini)

A lightweight macOS menu bar terminal.

Termini lives in your menu bar and gives you instant access to a full terminal session without leaving your current workflow.

If you find Termini useful, consider giving it a ⭐ — it helps others discover the project!

## Features



<table border="0">
  <tr>
    <td><img src="assets/images/Termini%20Desktop.png" width="400" alt="Landing"></td>
    <td><img src="assets/images/Termini%20XCode.png" width="400" alt="Landing"></td>
  </tr>
  <tr>
    <td><img src="assets/images/Termini%20Landing.png" width="400" alt="Landing"></td>
    <td><img src="assets/images/Termini%20Home.png" width="400" alt="Home"></td>
  </tr>
  <tr>
    <td><img src="assets/images/Termini%20Glow%202.png" width="400" alt="Glow"></td>
    <td><img src="assets/images/Termini%20Settings.png" width="400" alt="Settings"></td>
  </tr>
</table>

**Global shortcut** — Press ⌘E in any app to open or hide Termini. Record a different shortcut, or clear it, in Settings.

**Multi-tab sessions** — Open multiple terminal tabs in a single window (⌘T opens a new one, ⌘W closes it — on the last tab, ⌘W just hides the window). Each tab tracks the current working directory and displays it as the tab title, updated in real time via `proc_pidinfo`.

**Themes** — Choose from six built-in color schemes: Classic, Dracula, Nord, Solarized, Gruvbox, and Matrix. A custom theme option lets you set your own background and foreground colors via hex input.

**Adjustable opacity** — Slide the background opacity from fully transparent to fully opaque, useful for keeping the terminal visible over other windows.

**Font size control** — Increase or decrease the terminal font size (8–24pt) from the settings popover.

**Window sizes** — Four preset sizes to fit your screen: Mini (400×240), Medium (620×420), Large (820×540), and Full Screen.

**Open in external terminal** — Instantly open the active tab's current directory in any installed terminal app (Terminal.app, iTerm2, Ghostty, Warp, Alacritty).

**Login item** — Optionally launch Termini automatically at login via the Settings popover.


## Installation

### Download (recommended)

1. Go to the [latest release](https://github.com/ModernProgrammer/Termini/releases/latest).
2. Download `Termini.dmg` and open it.
3. Drag **Termini** into the `Applications` folder shown in the window.
4. Launch it from `/Applications` — Termini appears in your menu bar.

The download is a universal build (Apple Silicon + Intel) and is notarized by Apple, so it opens without a Gatekeeper warning.

### Build from source

Requirements:

- macOS 26+ (Apple Silicon or Intel)
- Xcode 26+ — the project targets macOS 26
- Xcode's Metal Toolchain component — SwiftTerm compiles Metal shaders, and newer Xcode versions no longer bundle the toolchain. Install it once with `xcodebuild -downloadComponent MetalToolchain` (or Xcode → Settings → Components).
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (resolved automatically as Swift Package dependencies)

Open `Termini.xcodeproj` in Xcode and build the `Termini` scheme. The app will appear in your menu bar on launch.

The project is set up with the maintainer's development team, so for your own builds pick your team (or **Sign to Run Locally**) under the target's *Signing & Capabilities* tab. From the command line you can skip that and ad-hoc sign instead:

```sh
xcodebuild -project Termini.xcodeproj -scheme Termini -configuration Debug \
  -derivedDataPath build/dd DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- build
open build/dd/Build/Products/Debug/Termini.app
```

There is no test suite yet.
