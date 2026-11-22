import Foundation

enum Preferences {
    enum Key {
        static let paused = "capturePaused"
        static let watchScreenshots = "watchScreenshotFolder"
        static let ocr = "ocrOnCapture"
        static let stitchSpacing = "stitchDividerSpacing"
        static let maxItems = "maxHistoryItems"
        static let autoUpdate = "autoCheckUpdates"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.watchScreenshots: true,
            Key.ocr: true,
            Key.stitchSpacing: true,
            Key.maxItems: 1000,
        ])
    }

    static var capturePaused: Bool {
        get { UserDefaults.standard.bool(forKey: Key.paused) }
        set { UserDefaults.standard.set(newValue, forKey: Key.paused) }
    }
    static var watchScreenshots: Bool {
        get { UserDefaults.standard.bool(forKey: Key.watchScreenshots) }
        set { UserDefaults.standard.set(newValue, forKey: Key.watchScreenshots) }
    }
    static var ocrEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.ocr) }
        set { UserDefaults.standard.set(newValue, forKey: Key.ocr) }
    }
    /// Off by default: ClipStick makes no network calls unless the user opts in or clicks "Check for Updates…".
    static var autoCheckUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: Key.autoUpdate) }
        set { UserDefaults.standard.set(newValue, forKey: Key.autoUpdate) }
    }
    static var stitchSpacing: Bool { UserDefaults.standard.bool(forKey: Key.stitchSpacing) }
    static var maxItems: Int { max(50, UserDefaults.standard.integer(forKey: Key.maxItems)) }
}
