//
//  TerminiApp.swift
//  Termini
//

import SwiftUI
import AppKit
import KeyboardShortcuts

// MARK: - Global shortcut

extension KeyboardShortcuts.Name {
    /// Opens or hides Termini from any app. Users can re-record it in Settings.
    static let toggleTermini = Self("toggleTermini", initial: .init(.e, modifiers: .command))
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menuBar = MenuBarController(store: TerminalStore())
        self.menuBar = menuBar

        // Global shortcut (⌘E by default) → open/close the terminal panel.
        KeyboardShortcuts.onKeyDown(for: .toggleTermini) {
            menuBar.toggle()
        }
    }
}

// MARK: - App

@main
struct TerminiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The menu bar icon and terminal panel live in MenuBarController.
        // SwiftUI still needs a scene: an empty Settings scene never opens a
        // window, and keeps the default main menu whose Edit items give the
        // terminal ⌘C / ⌘V / ⌘A.
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}
