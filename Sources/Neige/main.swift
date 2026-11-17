import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem!
    private let toggleItem = NSMenuItem(title: "Désactiver l’effet", action: #selector(toggle), keyEquivalent: "")
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private let versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let overlay = SnowOverlay()
    private let settings = Settings()
    private var sleeping = false
    private var screenSleeping = false
    private var locked = false
    private var screensaver = false
    private var active: Bool { settings.enabled && settings.amount > 0 && !sleeping && !screenSleeping && !locked && !screensaver }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "❄️"
        statusItem.button?.toolTip = "Sillage \(version)"
        let menu = NSMenu()
        menu.addItem(versionItem)
        let diagnostic = NSMenuItem(title: "Copier le diagnostic des fenêtres", action: #selector(copyDiagnostic), keyEquivalent: "")
        diagnostic.target = self
        menu.addItem(diagnostic)
        menu.addItem(.separator())
        toggleItem.target = self
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: "Ouvrir les réglages…", action: #selector(showWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter Sillage", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Sillage")
        let mainSettings = NSMenuItem(title: "Réglages…", action: #selector(showWindow), keyEquivalent: ",")
        mainSettings.target = self
        appMenu.addItem(mainSettings)
        let mainQuit = NSMenuItem(title: "Quitter Sillage", action: #selector(quitApp), keyEquivalent: "q")
        mainQuit.target = self
        appMenu.addItem(mainQuit)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(displaySleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(displayWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        let dc = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "com.apple.screensaver.didstart", "com.apple.screensaver.didstop"] {
            dc.addObserver(self, selector: #selector(sessionEvent(_:)), name: NSNotification.Name(name), object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .NSCalendarDayChanged, object: nil)
        settings.onChange = { [weak self] in self?.refresh() }
        overlay.rebuild(active: active)
        refresh()
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    @objc private func copyDiagnostic() {
        let ledges = WindowGeometry.visibleLedges(windows: true, dock: true)
        var lines = ["Sillage \(version)", "App : \(Bundle.main.bundlePath)", "Plein écran : \(WindowGeometry.fullscreenFrames)"]
        for ledge in ledges {
            let app = NSRunningApplication(processIdentifier: ledge.ownerPID)?.bundleIdentifier ?? "inconnu"
            lines.append("\(app) id=\(ledge.id) rect=\(ledge.frame) bords=\(ledge.spans) hauteur=\(ledge.maxSnowHeight)")
        }
        lines += ["Événements récents :"] + SnowDiagnostics.events
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc private func toggle() { settings.enabled.toggle() }
    @objc private func refresh() {
        versionItem.title = "Sillage \(version) — \(settings.season.rawValue)"
        overlay.apply(settings)
        overlay.setActive(active)
        toggleItem.title = settings.enabled ? "Désactiver l’effet" : "Activer l’effet"
        statusItem.button?.toolTip = active ? "Sillage active" : "Sillage en pause"
    }
    @objc private func willSleep() { sleeping = true; refresh() }
    @objc private func didWake() { sleeping = false; refresh() }
    @objc private func displaySleep() { screenSleeping = true; refresh() }
    @objc private func displayWake() { screenSleeping = false; refresh() }
    @objc private func sessionEvent(_ note: Notification) {
        switch note.name.rawValue {
        case "com.apple.screenIsLocked": locked = true
        case "com.apple.screenIsUnlocked": locked = false
        case "com.apple.screensaver.didstart": screensaver = true
        case "com.apple.screensaver.didstop": screensaver = false
        default: break
        }
        refresh()
    }
    @objc private func screensChanged() { overlay.rebuild(active: active); refresh() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 424, height: 320),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Sillage"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ControlsView(settings: settings, close: { [weak self] in self?.window?.close() }, plow: { [weak self] in self?.overlay.sendSnowplow() }))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
