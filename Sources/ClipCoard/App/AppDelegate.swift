import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var storage: StorageService!
    private var monitor: PasteboardMonitor!
    private var writer: ClipboardWriter!
    private var ingest: IngestService!
    private var vm: ClipboardViewModel!
    private var window: ClipboardWindowController!
    private var status: StatusItemController!
    private let watcher = ScreenshotFolderWatcher()
    private let hotkey = GlobalHotkeyService()

    var hotkeyLabel: String { hotkey.label }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        installMainMenu()

        do {
            storage = try StorageService()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "ClipStick can't start"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        // Drag-export copies from previous runs are disposable.
        try? FileManager.default.removeItem(at: storage.exportsURL)
        try? FileManager.default.createDirectory(at: storage.exportsURL, withIntermediateDirectories: true)
        storage.prune(maxItems: Preferences.maxItems)

        monitor = PasteboardMonitor()
        monitor.isPaused = Preferences.capturePaused
        writer = ClipboardWriter(storage: storage, monitor: monitor)
        ingest = IngestService(storage: storage)
        vm = ClipboardViewModel(storage: storage, writer: writer, ingest: ingest)
        window = ClipboardWindowController(vm: vm)

        ingest.onUpsert = { [weak vm] item in vm?.upsert(item) }
        ingest.onRemoved = { [weak vm] ids in vm?.remove(ids: ids) }
        monitor.onCapture = { [weak ingest] draft in ingest?.ingest(draft) }
        monitor.start()

        watcher.onScreenshot = { [weak self] url in
            guard let self, !Preferences.capturePaused else { return }
            self.ingest.ingest(CaptureDraft(
                payload: .imageFile(url), title: url.deletingPathExtension().lastPathComponent,
                sourceApp: "Screenshot", sourceBundleID: "com.apple.screencaptureui"))
        }
        if Preferences.watchScreenshots { watcher.start() }

        hotkey.onTrigger = { [weak self] in self?.window.toggle() }
        hotkey.register()

        status = StatusItemController(app: self)
        enableLaunchAtLoginOnFirstInstall()
    }

    // MARK: Launch at login

    var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ClipCoard: launch-at-login change failed: %@", error.localizedDescription)
        }
    }

    /// First run from an installed copy (/Applications or ~/Applications) turns launch-at-login on once;
    /// after that the menu toggle is the user's choice.
    private func enableLaunchAtLoginOnFirstInstall() {
        let key = "didConfigureLaunchAtLogin"
        let path = Bundle.main.bundlePath
        let installed = path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        guard installed, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        setLaunchAtLogin(true)
    }

    // MARK: Actions used by the status menu

    func showHUD() { window.show() }

    func setPaused(_ paused: Bool) {
        Preferences.capturePaused = paused
        monitor.isPaused = paused
    }

    func setWatchScreenshots(_ on: Bool) {
        Preferences.watchScreenshots = on
        if on { watcher.start() } else { watcher.stop() }
    }

    func openDataFolder() { NSWorkspace.shared.open(storage.rootURL) }

    func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "All clips except favorites are permanently deleted, including their saved screenshots."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let doomed = vm.items.filter { !$0.isFavorite }
        for item in doomed {
            storage.delete(id: item.id)
            storage.removeFiles(for: item)
        }
        vm.remove(ids: doomed.map(\.id))
    }

    // MARK: Menu

    /// An accessory app has no menu bar, but text fields still need Edit key equivalents (⌘V, ⌘A, ⌘Z…).
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ClipStick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}
