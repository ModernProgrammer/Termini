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

**Welcome screen** — An animated splash screen on first launch with a typing demo.

**Multi-tab sessions** — Open multiple terminal tabs in a single window. Each tab tracks the current working directory and displays it as the tab title, updated in real time via `proc_pidinfo`.

**Themes** — Choose from six built-in color schemes: Classic, Dracula, Nord, Solarized, Gruvbox, and Matrix. A custom theme option lets you set your own background and foreground colors via hex input.

**Adjustable opacity** — Slide the background opacity from fully transparent to fully opaque, useful for keeping the terminal visible over other windows.

**Font size control** — Increase or decrease the terminal font size (8–24pt) from the settings popover.

**Window sizes** — Four preset sizes to fit your screen: Mini (400×240), Medium (620×420), Large (820×540), and Full Screen.

**Open in external terminal** — Instantly open the active tab's current directory in any installed terminal app (Terminal.app, iTerm2, Ghostty, Warp, Alacritty).

**Login item** — Optionally launch Termini automatically at login via the Settings popover.


## Requirements

- macOS (Apple Silicon or Intel)
- Xcode 15+
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (Swift Package dependency)

## Building

Open `Termini.xcodeproj` in Xcode and build the `Termini` scheme. The app will appear in your menu bar on launch.
