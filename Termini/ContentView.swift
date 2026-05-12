// 
//  ContentView.swift
//  Termini
//

import SwiftUI
import SwiftTerm
import AppKit
import ServiceManagement

// MARK: - CWD helper (proc_pidinfo, no bridging header needed)

@_silgen_name("proc_pidinfo")
private func __proc_pidinfo(
    _ pid: Int32, _ flavor: Int32, _ arg: UInt64,
    _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32
) -> Int32

/// Returns the cwd of the given process via PROC_PIDVNODEPATHINFO (flavor 9).
/// Struct layout on 64-bit macOS: vnode_info = 152 bytes → path starts at offset 152.
private func cwdForPid(_ pid: pid_t) -> String? {
    guard pid > 0 else { return nil }
    let bufferSize = 2352
    let pathOffset  = 152
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    let ret = buffer.withUnsafeMutableBytes { ptr in
        __proc_pidinfo(pid, 9, 0, ptr.baseAddress, Int32(bufferSize))
    }
    guard ret > 0 else { return nil }
    return buffer.withUnsafeBytes { ptr in
        let p = ptr.baseAddress!.advanced(by: pathOffset).assumingMemoryBound(to: CChar.self)
        let s = String(cString: p)
        return s.isEmpty ? nil : s
    }
}

// MARK: - TerminalApp

fileprivate struct TerminalApp: Identifiable {
    let name: String
    let bundleId: String
    var id: String { bundleId }
    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) }
    var isInstalled: Bool { url != nil }
}

fileprivate let knownTerminals: [TerminalApp] = [
    TerminalApp(name: "Terminal",  bundleId: "com.apple.Terminal"),
    TerminalApp(name: "iTerm2",    bundleId: "com.googlecode.iterm2"),
    TerminalApp(name: "Ghostty",   bundleId: "com.mitchellh.ghostty"),
    TerminalApp(name: "Warp",      bundleId: "dev.warp.Warp-Stable"),
    TerminalApp(name: "Alacritty", bundleId: "io.alacritty"),
]

// MARK: - TerminalProcessDelegate

fileprivate final class TerminalProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    var currentDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    var onDirectoryChange: ((String) -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let dir = directory, !dir.isEmpty else { return }
        if let url = URL(string: dir), url.scheme == "file" {
            currentDirectory = url.path
        } else {
            currentDirectory = dir
        }
        onDirectoryChange?(currentDirectory)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}

// MARK: - TerminalTab

/// One terminal session. Created only by TerminalStore.
@Observable
final class TerminalTab: Identifiable {
    let id = UUID()

    @ObservationIgnored let terminalView: LocalProcessTerminalView
    @ObservationIgnored fileprivate let processDelegate: TerminalProcessDelegate

    var title: String = "~"

    @ObservationIgnored private var cwdTimer: Timer?

    fileprivate init(theme: TerminalTheme, fontSize: CGFloat, opacity: Double = 1.0) {
        terminalView    = LocalProcessTerminalView(frame: .zero)
        processDelegate = TerminalProcessDelegate()

        terminalView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.processDelegate = processDelegate

        let shell   = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env     = ProcessInfo.processInfo.environment
        env["TERM"]      = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        let envList = env.map { "\($0.key)=\($0.value)" }
        let home    = FileManager.default.homeDirectoryForCurrentUser.path
        terminalView.startProcess(executable: shell, args: ["-l"],
                                  environment: envList, currentDirectory: home)
        applyTheme(theme, opacity: opacity)

        // Poll cwd every second via proc_pidinfo — reliable regardless of shell config.
        cwdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pid = self.terminalView.process.shellPid
            guard let dir = cwdForPid(pid) else { return }
            let name = URL(fileURLWithPath: dir).lastPathComponent
            let label = name.isEmpty ? "~" : name
            if self.title != label {
                DispatchQueue.main.async { self.title = label }
            }
        }
    }

    deinit { cwdTimer?.invalidate() }

    fileprivate func applyTheme(_ theme: TerminalTheme, opacity: Double = 1.0) {
        // Always use a fully transparent background on the SwiftTerm view itself.
        // The visible background color + opacity are rendered by the SwiftUI ZStack
        // layer beneath, which lets the opacity slider and glass effect work correctly.
        terminalView.nativeBackgroundColor = .clear
        terminalView.nativeForegroundColor = theme.foreground
        terminalView.installColors(theme.makeSwiftTermColors())
    }
}

// MARK: - WindowSize

enum WindowSize: String, CaseIterable, Identifiable {
    case mini   = "mini"
    case medium = "medium"
    case large  = "large"
    case full   = "full"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mini:   return "S"
        case .medium: return "M"
        case .large:  return "L"
        case .full:   return "F"
        }
    }

    var helpText: String {
        switch self {
        case .mini:   return "Mini (400 × 240)"
        case .medium: return "Medium (620 × 420)"
        case .large:  return "Large (820 × 540)"
        case .full:   return "Full Screen"
        }
    }

    var terminalSize: CGSize {
        switch self {
        case .mini:   return CGSize(width: 400,  height: 240)
        case .medium: return CGSize(width: 620,  height: 420)
        case .large:  return CGSize(width: 820,  height: 540)
        case .full:
            let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 877)
            let width  = min(screen.width * 0.65, 1000)
            let height = screen.height * 0.85 - 36
            return CGSize(width: width, height: height)
        }
    }
}

// MARK: - TerminalStore

@Observable
final class TerminalStore {
    var tabs: [TerminalTab] = []
    var activeTabIndex: Int = 0

    var activeTab: TerminalTab { tabs[min(activeTabIndex, tabs.count - 1)] }

    var currentTheme: TerminalTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.id, forKey: "themeId")
            tabs.forEach { $0.applyTheme(currentTheme, opacity: backgroundOpacity) }
        }
    }

    var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(fontSize), forKey: "fontSize")
            tabs.forEach {
                $0.terminalView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        }
    }

    var windowSize: WindowSize {
        didSet { UserDefaults.standard.set(windowSize.rawValue, forKey: "windowSize") }
    }

    /// 0.0 = fully transparent background, 1.0 = fully opaque.
    var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "backgroundOpacity") }
    }

    var customBackground: NSColor {
        didSet {
            saveColor(customBackground, forKey: "customBackground")
            if currentTheme.id == "custom" {
                currentTheme = .custom(background: customBackground, foreground: customForeground)
            }
        }
    }

    var customForeground: NSColor {
        didSet {
            saveColor(customForeground, forKey: "customForeground")
            if currentTheme.id == "custom" {
                currentTheme = .custom(background: customBackground, foreground: customForeground)
            }
        }
    }

    var hasSeenWelcome: Bool = false

    init() {
        let savedId      = UserDefaults.standard.string(forKey: "themeId") ?? "classic"
        let savedFontSz  = CGFloat(UserDefaults.standard.double(forKey: "fontSize"))
        let size         = savedFontSz > 0 ? savedFontSz : 12
        let savedWinId   = UserDefaults.standard.string(forKey: "windowSize") ?? "medium"
        let savedWinSize = WindowSize(rawValue: savedWinId) ?? .medium
        let savedOpacity = UserDefaults.standard.object(forKey: "backgroundOpacity") as? Double ?? 1.0
        let savedBg      = TerminalStore.loadColor(forKey: "customBackground") ?? .init(hex: 0x1C1C1C)
        let savedFg      = TerminalStore.loadColor(forKey: "customForeground") ?? .init(hex: 0xF0F0F0)

        customBackground = savedBg
        customForeground = savedFg

        let savedTheme: TerminalTheme
        if savedId == "custom" {
            savedTheme = .custom(background: savedBg, foreground: savedFg)
        } else {
            savedTheme = TerminalTheme.all.first(where: { $0.id == savedId }) ?? .classic
        }

        currentTheme      = savedTheme
        fontSize          = size
        windowSize        = savedWinSize
        backgroundOpacity = savedOpacity
        tabs              = [TerminalTab(theme: savedTheme, fontSize: size)]
    }

    private func saveColor(_ color: NSColor, forKey key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadColor(forKey key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    func addTab() {
        tabs.append(TerminalTab(theme: currentTheme, fontSize: fontSize, opacity: backgroundOpacity))
        activeTabIndex = tabs.count - 1
    }

    func removeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        if activeTabIndex >= tabs.count { activeTabIndex = tabs.count - 1 }
    }

    fileprivate var installedTerminals: [TerminalApp] {
        knownTerminals.filter(\.isInstalled)
    }

    fileprivate func openCurrentDirectory(in terminal: TerminalApp) {
        guard let appURL = terminal.url else { return }
        let shellPid = activeTab.terminalView.process.shellPid
        let dir = cwdForPid(shellPid) ?? activeTab.processDelegate.currentDirectory

        if terminal.bundleId == "com.mitchellh.ghostty" {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", "-a", appURL.path, "--args",
                              "--working-directory=\(dir)"]
            try? task.run()
        } else {
            let dirURL = URL(fileURLWithPath: dir)
            NSWorkspace.shared.open([dirURL], withApplicationAt: appURL,
                                     configuration: .init(), completionHandler: nil)
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(TerminalStore.self) var store
    @State private var showSettings = false

    var body: some View {
        ZStack {
            if store.hasSeenWelcome {
                terminalContent
                    .transition(.opacity)
            } else {
                WelcomeView(size: store.windowSize.terminalSize) {
                    store.hasSeenWelcome = true
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: store.hasSeenWelcome)
    }

    // MARK: Terminal content

    private var terminalContent: some View {
        let ts = store.windowSize.terminalSize
        return VStack(spacing: 0) {
            toolbar
            ZStack {
                // Read customBackground directly so SwiftUI re-renders on every change.
                // (TerminalTheme equality is id-only, so "custom" → "custom" would be skipped.)
                let bg = store.currentTheme.id == "custom"
                    ? store.customBackground
                    : store.currentTheme.background
                Color(bg)
                    .opacity(store.backgroundOpacity)
                TerminalWrapper(view: store.activeTab.terminalView)
                    .id(store.activeTab.id)
                    .padding(8)
            }
            .frame(width: ts.width, height: ts.height)
        }
        .animation(.spring(duration: 0.35, bounce: 0.1), value: store.windowSize)
        .onAppear { focusActiveTab() }
        .onChange(of: store.activeTabIndex) { _, _ in focusActiveTab() }
    }

    private var toolbarIcon: NSImage {
        guard let icon = NSImage(named: "Termini Menu Icon") else {
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) ?? NSImage()
        }
        let size = NSSize(width: 14, height: 14)
        let scaled = NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            return true
        }
        scaled.isTemplate = false
        return scaled
    }

    private func focusActiveTab() {
        DispatchQueue.main.async {
            let tv = store.activeTab.terminalView
            tv.window?.makeFirstResponder(tv)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        let ts   = store.windowSize.terminalSize
        let mini = store.windowSize == .mini
        return HStack(spacing: 0) {

            // App icon + title
            HStack(spacing: 5) {
                Image(nsImage: toolbarIcon)
                    .renderingMode(.original)
                if !mini {
                    Text("Termini")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 10)
            .padding(.trailing, 6)

            // Tabs
            HStack(spacing: 2) {
                ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabPill(index: index, tab: tab)
                }
            }

            // New tab
            Button { store.addTab() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New Tab")
            .padding(.leading, 2)

            Spacer(minLength: 4)

            // Open in external terminal
            openButton

            // Settings
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
            .popover(isPresented: $showSettings, arrowEdge: .top) {
                SettingsView()
                    .environment(store)
            }

            Spacer().frame(width: 4)
        }
        .frame(width: ts.width, height: 36)
        .background {
            let bg = store.currentTheme.id == "custom"
                ? store.customBackground
                : store.currentTheme.background
            Color(bg).opacity(max(store.backgroundOpacity, 0.15))
        }
    }

    private func tabPill(index: Int, tab: TerminalTab) -> some View {
        let isActive = index == store.activeTabIndex
        return HStack(spacing: 3) {
            Text(tab.title)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: 72)
            if store.tabs.count > 1 {
                Button {
                    store.removeTab(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 0.8 : 0.4)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.03))
        )
        .foregroundStyle(isActive ? .primary : .secondary)
        .contentShape(Rectangle())
        .onTapGesture { store.activeTabIndex = index }
        .animation(.spring(duration: 0.2), value: isActive)
    }

    @ViewBuilder
    private var openButton: some View {
        let installed = store.installedTerminals
        if !installed.isEmpty {
            if installed.count == 1 {
                Button { store.openCurrentDirectory(in: installed[0]) } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 26, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open in \(installed[0].name)")
            } else {
                Menu {
                    ForEach(installed) { app in
                        Button(app.name) { store.openCurrentDirectory(in: app) }
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 26, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Open in terminal…")
            }
            toolbarDivider
        }
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 14)
            .padding(.horizontal, 4)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(TerminalStore.self) var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Theme
            settingsRow("Theme") {
                HStack(spacing: 8) {
                    ForEach(TerminalTheme.all) { theme in
                        let isActive = theme.id == store.currentTheme.id
                        Button { store.currentTheme = theme } label: {
                            Circle()
                                .fill(theme.swatch)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(isActive ? 0.9 : 0),
                                                      lineWidth: 1.5)
                                        .padding(-2)
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(duration: 0.2), value: isActive)
                    }

                    // Custom theme swatch — half bg / half fg split circle
                    let isCustom = store.currentTheme.id == "custom"
                    Button {
                        store.currentTheme = .custom(
                            background: store.customBackground,
                            foreground: store.customForeground
                        )
                    } label: {
                        ZStack {
                            SwiftUI.Color(store.customBackground)
                            HStack(spacing: 0) {
                                SwiftUI.Color.clear.frame(width: 9)
                                SwiftUI.Color(store.customForeground).frame(width: 9)
                            }
                        }
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(isCustom ? 0.9 : 0),
                                              lineWidth: 1.5)
                                .padding(-2)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Custom")
                    .animation(.spring(duration: 0.2), value: isCustom)
                }
            }

            // Custom color pickers — only visible when custom theme is active
            if store.currentTheme.id == "custom" {
                settingsDivider

                settingsRow("Background") {
                    HexColorPicker(label: "Background", color: Binding(
                        get: { store.customBackground },
                        set: { store.customBackground = $0 }
                    ))
                }

                settingsRow("Text") {
                    HexColorPicker(label: "Text", color: Binding(
                        get: { store.customForeground },
                        set: { store.customForeground = $0 }
                    ))
                }
            }

            settingsDivider

            settingsRow("Opacity") {
                @Bindable var store = store
                HStack(spacing: 8) {
                    Slider(value: $store.backgroundOpacity, in: 0.0...1.0, step: 0.05)
                        .frame(width: 150)
                    Text("\(Int(store.backgroundOpacity * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            settingsDivider

            // Font size
            settingsRow("Font Size") {
                HStack(spacing: 0) {
                    Button { store.fontSize = max(8, store.fontSize - 1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Text("\(Int(store.fontSize))")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 28, alignment: .center)

                    Button { store.fontSize = min(24, store.fontSize + 1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            settingsDivider

            // Window size
            settingsRow("Window Size") {
                HStack(spacing: 4) {
                    ForEach(WindowSize.allCases) { ws in
                        let isActive = ws == store.windowSize
                        Button { store.windowSize = ws } label: {
                            Text(ws.label)
                                .font(.system(size: 11, weight: isActive ? .bold : .regular,
                                              design: .monospaced))
                                .foregroundStyle(isActive ? .primary : .secondary)
                                .frame(width: 34, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.02))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(ws.helpText)
                        .animation(.spring(duration: 0.2), value: isActive)
                    }
                }
            }

            settingsDivider

            settingsRow("Login") {
                Toggle("Open at Login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { enable in
                        if enable { try? SMAppService.mainApp.register() }
                        else      { try? SMAppService.mainApp.unregister() }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            settingsDivider

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Text("Quit Termini")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.75))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 310)
    }

    private func settingsRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var settingsDivider: some View {
        Divider().padding(.horizontal, 16)
    }
}

// MARK: - WelcomeView

struct WelcomeView: View {
    var size: CGSize
    var onDismiss: () -> Void

    @State private var showContent = false
    @State private var typedText   = ""
    @State private var cursorOn    = true
    @State private var typingTask: Task<Void, Never>? = nil

    private let commands = [
        "git status",
        "npm run dev",
        "ls -la",
        "python3 manage.py runserver",
        "docker ps",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(nsImage: {
                    guard let icon = NSImage(named: "Termini Menu Icon") else {
                        return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil) ?? NSImage()
                    }
                    let size = NSSize(width: 72, height: 72)
                    let scaled = NSImage(size: size, flipped: false) { rect in
                        icon.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
                        return true
                    }
                    scaled.isTemplate = false
                    return scaled
                }())
                .renderingMode(.original)
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.8)

                VStack(spacing: 6) {
                    Text("Termini")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                    Text("Your terminal, right in the menu bar.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .opacity(showContent ? 1 : 0)

                HStack(spacing: 0) {
                    Text("% ")
                        .foregroundStyle(.green)
                    Text(typedText)
                    Rectangle()
                        .frame(width: 7, height: 14)
                        .opacity(cursorOn ? 1 : 0)
                }
                .font(.system(size: 13, design: .monospaced))
                .frame(width: min(size.width - 80, 280), alignment: .leading)
                .opacity(showContent ? 1 : 0)
            }

            Spacer()

            Button("Open Terminal  →") {
                typingTask?.cancel()
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 36)
            .opacity(showContent ? 1 : 0)
        }
        .frame(width: size.width, height: size.height + 36)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.3)) { showContent = true }
            typingTask = Task { await runTypingLoop() }
            Task { await blinkCursor() }
        }
        .onDisappear { typingTask?.cancel() }
    }

    private func runTypingLoop() async {
        try? await Task.sleep(for: .milliseconds(700))
        while !Task.isCancelled {
            for command in commands {
                if Task.isCancelled { return }
                for char in command {
                    if Task.isCancelled { return }
                    typedText.append(char)
                    try? await Task.sleep(for: .milliseconds(75))
                }
                try? await Task.sleep(for: .milliseconds(1100))
                while !typedText.isEmpty {
                    if Task.isCancelled { return }
                    typedText.removeLast()
                    try? await Task.sleep(for: .milliseconds(35))
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func blinkCursor() async {
        while true {
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.linear(duration: 0.01)) { cursorOn.toggle() }
        }
    }
}

// MARK: - HexColorPicker

/// Inline hex color input that stays inside the popover — avoids NSColorPanel stealing focus.
struct HexColorPicker: View {
    let label: String
    @Binding var color: NSColor

    @State private var hexText: String = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Live color swatch
            RoundedRectangle(cornerRadius: 4)
                .fill(SwiftUI.Color(color))
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))

            // Hex field
            HStack(spacing: 4) {
                Text("#")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("", text: $hexText)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .frame(width: 68)
                    .focused($focused)
                    .onAppear { hexText = color.hexString }
                    .onChange(of: color) { _, newColor in
                        if !focused { hexText = newColor.hexString }
                    }
                    .onChange(of: hexText) { _, newHex in
                        let clean = newHex.trimmingCharacters(in: .init(charactersIn: "#"))
                        if clean.count == 6, let parsed = NSColor(hexString: clean) {
                            color = parsed
                        }
                    }
                    .onSubmit {
                        hexText = color.hexString
                        focused = false
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.07)))
        }
    }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "000000" }
        return String(format: "%02X%02X%02X",
                      Int(rgb.redComponent * 255),
                      Int(rgb.greenComponent * 255),
                      Int(rgb.blueComponent * 255))
    }

    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .init(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

// MARK: - TerminalWrapper

struct TerminalWrapper: NSViewRepresentable {
    let view: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        // Allow the Metal layer to composite transparently over whatever is behind it.
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
