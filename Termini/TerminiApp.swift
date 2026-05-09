//
//  TerminiApp.swift
//  Termini
//

import SwiftUI
import AppKit

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Right-click on the menu bar icon → show a Quit menu.
        // Status bar events have no associated NSWindow, so event.window == nil.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard event.window == nil else { return event }
            let menu = NSMenu()
            let quit = menu.addItem(
                withTitle: "Quit Termini",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
            quit.target = NSApp
            _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return nil
        }
    }

    deinit {
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    }
}

// MARK: - App

@main
struct TerminiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = TerminalStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: NSImage {
        guard let icon = NSImage(named: "Termini Menu Icon") else {
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) ?? NSImage()
        }
        let size = NSSize(width: 18, height: 18)
        let menuBarIcon = NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            return true
        }
        menuBarIcon.isTemplate = false
        return menuBarIcon
    }
}
