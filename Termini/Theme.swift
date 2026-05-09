//
//  Theme.swift
//  Termini
//

import SwiftUI
import SwiftTerm
import AppKit

struct TerminalTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let background: NSColor
    let foreground: NSColor
    let ansi16: [UInt32]          // 16 ANSI colors as 0xRRGGBB
    let swatch: SwiftUI.Color     // dot shown in the toolbar picker

    // Equality and hashing are based on id only so NSColor doesn't need to conform.
    static func == (lhs: TerminalTheme, rhs: TerminalTheme) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: Built-in themes

    static let all: [TerminalTheme] = [.classic, .nord, .solarized, .gruvbox, .matrix]

    /// Build a custom theme from user-chosen colors.
    /// ANSI colors fall back to Classic so colored output still looks reasonable.
    static func custom(background: NSColor, foreground: NSColor) -> TerminalTheme {
        TerminalTheme(
            id: "custom", name: "Custom",
            background: background,
            foreground: foreground,
            ansi16: TerminalTheme.classic.ansi16,
            swatch: SwiftUI.Color(background)
        )
    }

    static let classic = TerminalTheme(
        id: "classic", name: "Classic",
        background: .init(hex: 0x1C1C1C),
        foreground: .init(hex: 0xF0F0F0),
        ansi16: [
            0x1C1C1C, 0xCC0000, 0x4E9A06, 0xC4A000,
            0x3465A4, 0x75507B, 0x06989A, 0xD3D7CF,
            0x555753, 0xEF2929, 0x8AE234, 0xFCE94F,
            0x729FCF, 0xAD7FA8, 0x34E2E2, 0xEEEEEC,
        ],
        swatch: SwiftUI.Color(white: 0.85)
    )

    static let dracula = TerminalTheme(
        id: "dracula", name: "Dracula",
        background: .init(hex: 0x282A36),
        foreground: .init(hex: 0xF8F8F2),
        ansi16: [
            0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C,
            0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
            0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5,
            0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF,
        ],
        swatch: SwiftUI.Color(red: 0.741, green: 0.576, blue: 0.976)
    )

    static let nord = TerminalTheme(
        id: "nord", name: "Nord",
        background: .init(hex: 0x2E3440),
        foreground: .init(hex: 0xD8DEE9),
        ansi16: [
            0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B,
            0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
            0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B,
            0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4,
        ],
        swatch: SwiftUI.Color(red: 0.533, green: 0.753, blue: 0.816)
    )

    static let solarized = TerminalTheme(
        id: "solarized", name: "Solarized",
        background: .init(hex: 0x002B36),
        foreground: .init(hex: 0x839496),
        ansi16: [
            0x073642, 0xDC322F, 0x859900, 0xB58900,
            0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
            0x002B36, 0xCB4B16, 0x586E75, 0x657B83,
            0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
        ],
        swatch: SwiftUI.Color(red: 0.153, green: 0.545, blue: 0.824)
    )

    static let matrix = TerminalTheme(
        id: "matrix", name: "Matrix",
        background: .init(hex: 0x0D0208),
        foreground: .init(hex: 0x00FF41),
        ansi16: [
            0x0D0208, 0xFF0000, 0x00FF41, 0xAFFFAD,
            0x00B628, 0x008F11, 0x00FF41, 0xADFF2F,
            0x003B00, 0xFF4444, 0x00FF41, 0xAFFFAD,
            0x00B628, 0x008F11, 0x00FF41, 0xFFFFFF,
        ],
        swatch: SwiftUI.Color(red: 0, green: 1, blue: 0.255)
    )

    static let gruvbox = TerminalTheme(
        id: "gruvbox", name: "Gruvbox",
        background: .init(hex: 0x282828),
        foreground: .init(hex: 0xEBDBB2),
        ansi16: [
            0x282828, 0xCC241D, 0x98971A, 0xD79921,
            0x458588, 0xB16286, 0x689D6A, 0xA89984,
            0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F,
            0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2,
        ],
        swatch: SwiftUI.Color(red: 0.984, green: 0.722, blue: 0.196)
    )

    // MARK: Color conversion

    /// Full 256-entry palette: custom ANSI 0–15 + standard xterm 16–255.
    func makeSwiftTermColors() -> [SwiftTerm.Color] {
        // 0-15: custom ANSI colors
        var colors: [SwiftTerm.Color] = ansi16.map { stColor($0) }

        // 16-231: 6×6×6 color cube
        for r in 0 ..< 6 {
            for g in 0 ..< 6 {
                for b in 0 ..< 6 {
                    colors.append(SwiftTerm.Color(
                        red:   r == 0 ? 0 : UInt16(r * 40 + 55) * 257,
                        green: g == 0 ? 0 : UInt16(g * 40 + 55) * 257,
                        blue:  b == 0 ? 0 : UInt16(b * 40 + 55) * 257
                    ))
                }
            }
        }

        // 232-255: grayscale ramp
        for i in 0 ..< 24 {
            let v = UInt16(i * 10 + 8) * 257
            colors.append(SwiftTerm.Color(red: v, green: v, blue: v))
        }

        return colors
    }
}

// MARK: - Helpers

private func stColor(_ hex: UInt32) -> SwiftTerm.Color {
    SwiftTerm.Color(
        red:   UInt16((hex >> 16) & 0xFF) * 257,
        green: UInt16((hex >>  8) & 0xFF) * 257,
        blue:  UInt16( hex        & 0xFF) * 257
    )
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >>  8) & 0xFF) / 255,
            blue:  CGFloat( hex        & 0xFF) / 255,
            alpha: 1
        )
    }
}
