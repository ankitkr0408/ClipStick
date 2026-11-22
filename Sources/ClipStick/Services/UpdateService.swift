import AppKit
import CryptoKit

/// Self-updater: reads `version.json` from the GitHub repo, and (on the user's say-so) downloads the new build,
/// verifies its SHA-256, swaps the app bundle in place and relaunches. Nothing is ever sent beyond a plain HTTPS GET.
@MainActor
final class UpdateService {
    struct Manifest: Decodable {
        let version: String
        let url: URL
        let sha256: String
        let notes: String?
    }

    enum UpdateError: LocalizedError {
        case badResponse, untrustedURL, checksumMismatch, badBundle, notWritable
        var errorDescription: String? {
            switch self {
            case .badResponse: "The update server returned an unexpected response."
            case .untrustedURL: "The update isn't hosted on GitHub, so it was refused."
            case .checksumMismatch: "The downloaded file failed its integrity check."
            case .badBundle: "The downloaded file isn't a valid ClipStick build."
            case .notWritable: "ClipStick can't replace itself in its current folder."
            }
        }
    }

    static let manifestURL = URL(string: "https://raw.githubusercontent.com/ankitkr0408/ClipStick/main/version.json")!
    static let releasePage = URL(string: "https://github.com/ankitkr0408/ClipStick")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let trustedHosts: Set<String> = ["raw.githubusercontent.com", "github.com", "objects.githubusercontent.com"]

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var isBusy = false

    /// Automatic launch-time check: opt-in, at most once per 24 h, silent unless an update exists.
    func checkInBackgroundIfDue() {
        guard Preferences.autoCheckUpdates else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        Task { await check(interactive: false) }
    }

    func check(interactive: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let manifest = try await fetchManifest()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            if Self.isNewer(manifest.version, than: Self.currentVersion) {
                await promptToInstall(manifest)
            } else if interactive {
                alert("ClipStick is up to date", "You're running the latest version (\(Self.currentVersion)).")
            }
        } catch {
            if interactive { alert("Couldn't check for updates", error.localizedDescription) }
        }
    }

    // MARK: Fetch & compare

    private func fetchManifest() async throws -> Manifest {
        var req = URLRequest(url: Self.manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("ClipStick-Updater", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }
        guard let m = try? JSONDecoder().decode(Manifest.self, from: data) else { throw UpdateError.badResponse }
        guard m.url.scheme == "https", let host = m.url.host, Self.trustedHosts.contains(host) else { throw UpdateError.untrustedURL }
        return m
    }

    /// Dotted-numeric comparison ("0.10.0" > "0.9.0").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if p != q { return p > q }
        }
        return false
    }

    // MARK: Install

    private func promptToInstall(_ m: Manifest) async {
        let a = NSAlert()
        a.messageText = "ClipStick \(m.version) is available"
        a.informativeText = "You have \(Self.currentVersion)." + (m.notes.map { "\n\n\($0)" } ?? "") + "\n\nYour clipboard history is kept."
        a.addButton(withTitle: "Install & Relaunch")
        a.addButton(withTitle: "View on GitHub")
        a.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn:
            do { try await install(m) } catch {
                let fallback = NSAlert()
                fallback.messageText = "Update couldn't be installed"
                fallback.informativeText = error.localizedDescription + "\n\nYou can download it manually from GitHub."
                fallback.addButton(withTitle: "Open GitHub")
                fallback.addButton(withTitle: "Cancel")
                if fallback.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Self.releasePage) }
            }
        case .alertSecondButtonReturn: NSWorkspace.shared.open(Self.releasePage)
        default: break
        }
    }

    private func install(_ m: Manifest) async throws {
        let appURL = Bundle.main.bundleURL
        let parent = appURL.deletingLastPathComponent().path
        guard appURL.pathExtension == "app", FileManager.default.isWritableFile(atPath: parent) else { throw UpdateError.notWritable }

        let (tmpFile, resp) = try await URLSession.shared.download(from: m.url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }
        let zipData = try Data(contentsOf: tmpFile, options: .mappedIfSafe)
        let digest = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(m.sha256) == .orderedSame else { throw UpdateError.checksumMismatch }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("clipstick-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: tmpFile, to: zip)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

        let newApp = work.appendingPathComponent("ClipStick.app")
        let bundle = Bundle(url: newApp)
        guard bundle?.bundleIdentifier == Bundle.main.bundleIdentifier,
              (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) == m.version,
              FileManager.default.isExecutableFile(atPath: newApp.appendingPathComponent("Contents/MacOS/ClipStick").path)
        else { throw UpdateError.badBundle }

        // Detached helper: waits for this process to quit, swaps the bundle (restoring the old one on failure), relaunches.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        BACKUP="$2.old-$$"
        mv "$2" "$BACKUP" && { mv "$3" "$2" && rm -rf "$BACKUP" || mv "$BACKUP" "$2"; }
        rm -rf "$4"
        open "$2"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script, "updater", String(ProcessInfo.processInfo.processIdentifier), appURL.path, newApp.path, work.path]
        try p.run()
        NSApp.terminate(nil)
    }

    private func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.badBundle }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
