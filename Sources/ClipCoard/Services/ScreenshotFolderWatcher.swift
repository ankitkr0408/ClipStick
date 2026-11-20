import Foundation

/// Watches the macOS screenshot destination so ⌘⇧4 captures (which only save a file and never
/// touch the pasteboard) are imported too. Uses a kqueue vnode source on the directory.
final class ScreenshotFolderWatcher {
    var onScreenshot: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var seen = Set<String>()
    private var pendingScan: DispatchWorkItem?
    private let directory: URL
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

    init(directory: URL = ScreenshotFolderWatcher.screenshotDirectory()) { self.directory = directory }

    static func screenshotDirectory() -> URL {
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !loc.isEmpty {
            return URL(fileURLWithPath: (loc as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    var isRunning: Bool { source != nil }

    func start() {
        guard source == nil else { return }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("ClipCoard: cannot watch %@ (permission?)", directory.path)
            return
        }
        // Existing files are not "new screenshots".
        seen = Set(contents().map(\.path))
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.scheduleScan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        pendingScan?.cancel()
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func contents() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    private func scan() {
        for url in contents() where !seen.contains(url.path) {
            guard Self.imageExtensions.contains(url.pathExtension.lowercased()), Self.isScreenshot(url) else { continue }
            seen.insert(url.path)
            onScreenshot?(url)
        }
    }

    /// macOS tags real screenshots with `kMDItemIsScreenCapture`; fall back to the default names.
    static func isScreenshot(_ url: URL) -> Bool {
        if getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0 { return true }
        let name = url.lastPathComponent
        return name.hasPrefix("Screenshot") || name.hasPrefix("Screen Shot")
    }
}
