import AppKit

@main
@MainActor
enum ClipStickApp {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
            _ = NSApplication.shared
            exit(Snapshot.run(outputDir: CommandLine.arguments[i + 1]))
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

/// The menu-bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private unowned let app: AppDelegate

    private let pauseItem = NSMenuItem()
    private let watchItem = NSMenuItem()
    private let ocrItem = NSMenuItem()
    private let showItem = NSMenuItem()
    private let loginItem = NSMenuItem()

    init(app: AppDelegate) {
        self.app = app
        super.init()

        let menu = NSMenu()
        menu.delegate = self

        showItem.action = #selector(show)
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())

        for (mi, title, sel) in [
            (pauseItem, "Pause Capturing", #selector(togglePause)),
            (watchItem, "Import Screenshots from Folder", #selector(toggleWatch)),
            (ocrItem, "Recognise Text in Screenshots (OCR)", #selector(toggleOCR)),
            (loginItem, "Launch at Login", #selector(toggleLogin)),
        ] {
            mi.title = title
            mi.action = sel
            mi.target = self
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Data Folder", action: #selector(openData), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Clear History…", action: #selector(clearHistory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipStick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        item.button?.toolTip = "ClipStick"
        updateIcon()
    }

    func updateIcon() {
        let name = Preferences.capturePaused ? "pause.circle" : "doc.on.clipboard"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "ClipStick")
        image?.isTemplate = true
        item.button?.image = image
    }

    func menuWillOpen(_ menu: NSMenu) {
        showItem.title = "Show ClipStick" + (app.hotkeyLabel.isEmpty ? "" : "    \(app.hotkeyLabel)")
        pauseItem.state = Preferences.capturePaused ? .on : .off
        watchItem.state = Preferences.watchScreenshots ? .on : .off
        ocrItem.state = Preferences.ocrEnabled ? .on : .off
        loginItem.state = app.launchAtLoginEnabled ? .on : .off
    }

    @objc private func show() { app.showHUD() }
    @objc private func togglePause() { app.setPaused(!Preferences.capturePaused); updateIcon() }
    @objc private func toggleWatch() { app.setWatchScreenshots(!Preferences.watchScreenshots) }
    @objc private func toggleOCR() { Preferences.ocrEnabled.toggle() }
    @objc private func toggleLogin() { app.setLaunchAtLogin(!app.launchAtLoginEnabled) }
    @objc private func openData() { app.openDataFolder() }
    @objc private func clearHistory() { app.confirmClearHistory() }
}
