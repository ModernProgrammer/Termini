//
//  MenuBarController.swift
//  Termini
//

import SwiftUI
import AppKit

// MARK: - MenuBarPanel

/// Borderless panel that hosts the terminal. Like a menu, it takes keyboard
/// focus without activating Termini, so the app you came from keeps the menu
/// bar and gets focus back as soon as the panel closes.
private final class MenuBarPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    // Borderless windows refuse key status by default — the terminal needs it.
    override var canBecomeKey: Bool { true }
}

// MARK: - MenuBarController

/// Owns the menu bar icon and the terminal panel beneath it, using only public
/// AppKit API so it can also be opened from code (the global shortcut).
@Observable
final class MenuBarController: NSObject {
    /// Keeps the panel open and floating above other windows when you click away.
    var isPinned = false {
        didSet { applyPinned() }
    }

    @ObservationIgnored private let statusItem: NSStatusItem
    @ObservationIgnored private let panel = MenuBarPanel()
    /// Size of the SwiftUI content, reported by the content itself.
    @ObservationIgnored private var contentSize: CGSize = .zero
    @ObservationIgnored private var outsideClickMonitor: Any?

    private static let cornerRadius: CGFloat = 16
    /// Space between the menu bar and the top of the panel.
    private static let menuBarGap: CGFloat = 6
    private static let screenMargin: CGFloat = 8

    init(store: TerminalStore) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.menuBarIcon
            button.setAccessibilityLabel("Termini")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        if #available(macOS 27.0, *) {
            // macOS 27 opens status item windows through an expanded interface
            // session, which also highlights the icon while the panel is open.
            statusItem.expandedInterfaceDelegate = self
        }

        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        let hostingView = NSHostingView(rootView: AnyView(
            ContentView()
                .environment(store)
                .environment(self)
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
                .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] size in
                    self?.contentSize = size
                    self?.layoutPanel()
                }
        ))
        // The panel follows the SwiftUI content size; see layoutPanel().
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        applyPinned()

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification, object: nil
        )
    }

    // MARK: Showing and hiding

    /// Opens the panel, focuses it if it's open behind another app, or closes it.
    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        if !panel.isVisible { layoutPanel() }
        panel.makeKeyAndOrderFront(nil)
        if #unavailable(macOS 27.0) { statusItem.button?.highlight(true) }
        watchForOutsideClicks()
    }

    /// Hides the panel; its terminal sessions keep running.
    func hide() {
        panel.orderOut(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if #available(macOS 27.0, *) {
            statusItem.expandedInterfaceSession?.cancel()
        } else {
            statusItem.button?.highlight(false)
        }
    }

    // MARK: Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuitMenu()
        } else {
            toggle()
        }
    }

    private func showQuitMenu() {
        let menu = NSMenu()
        let quit = menu.addItem(
            withTitle: "Quit Termini",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static var menuBarIcon: NSImage {
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

    // MARK: Layout

    /// Sizes the panel to its content and places it below the menu bar icon on
    /// the screen with the mouse pointer — where the icon was clicked, or where
    /// you're working when the shortcut is pressed.
    private func layoutPanel() {
        let size = contentSize
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return }

        var visible = screen.visibleFrame
        if visible.maxY >= screen.frame.maxY {
            // Auto-hidden menu bar: still leave room for it.
            visible.size.height -= NSStatusBar.system.thickness
        }

        // Open like a menu: left-aligned with the icon, flipped to right-aligned
        // when that would run off the screen.
        let icon = iconFrame(on: screen)
        var x = icon.minX
        if x + size.width > visible.maxX - Self.screenMargin {
            x = icon.maxX - size.width
        }
        x = min(x, visible.maxX - Self.screenMargin - size.width)
        x = max(x, visible.minX + Self.screenMargin)

        let y = visible.maxY - Self.menuBarGap - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    /// Where the menu bar icon sits on `screen`, in screen coordinates. The real
    /// icon lives on the display with the active menu bar; other displays show
    /// copies near the same distance from the right edge, so use that there.
    private func iconFrame(on screen: NSScreen) -> NSRect {
        guard let window = statusItem.button?.window,
              let iconScreen = window.screen else {
            // Icon hidden (e.g. behind the notch): fall back to the right edge.
            let maxX = screen.visibleFrame.maxX - Self.screenMargin
            return NSRect(x: maxX, y: screen.frame.maxY, width: 0, height: 0)
        }
        var frame = window.frame
        frame.origin.x += screen.frame.maxX - iconScreen.frame.maxX
        return frame
    }

    // MARK: Dismissal

    /// Switching to another app (e.g. with ⌘-Tab) closes the panel.
    @objc private func windowDidResignKey(_ notification: Notification) {
        // Focus may just be moving between our own windows (the panel and the
        // Settings popover); only react once none of them has it.
        DispatchQueue.main.async { [self] in
            guard NSApp.keyWindow == nil else { return }
            dismissAfterOutsideInteraction()
        }
    }

    /// Clicks outside Termini close the panel too. That includes clicks on our
    /// own menu bar icon on macOS 27, where the menu bar runs in another process
    /// and the click doesn't take focus from the panel. Ending the session on
    /// mouse-down also stops AppKit from reopening the panel for the same click.
    private func watchForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.dismissAfterOutsideInteraction()
        }
    }

    /// Closes the panel like a menu — unless it's pinned.
    private func dismissAfterOutsideInteraction() {
        guard panel.isVisible else { return }
        if isPinned {
            // Stay on screen, but let the menu bar know we're no longer open.
            if #available(macOS 27.0, *) { statusItem.expandedInterfaceSession?.cancel() }
        } else {
            hide()
        }
    }

    // MARK: Pinning

    private func applyPinned() {
        if isPinned {
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllApplications, .canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllApplications]
        }
    }
}

// MARK: - NSStatusItemExpandedInterfaceDelegate

@available(macOS 27.0, *)
extension MenuBarController: NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        toggle()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        // A pinned panel that has lost focus stays up after its session ends.
        if isPinned && !panel.isKeyWindow { return }
        hide()
    }
}
