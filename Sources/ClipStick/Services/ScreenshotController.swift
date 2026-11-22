import AppKit

/// Orchestrates "Take Screenshot" (⌥S):
/// Area drag selection → captures screen via ScreenCaptureKit → copies to clipboard + stores in ClipStick.
@MainActor
final class ScreenshotController {
    private let storage: StorageService
    private let ingest: IngestService
    private var selecting = false

    var onCaptured: (() -> Void)?
    var onMessage: ((String) -> Void)?

    init(storage: StorageService, ingest: IngestService) {
        self.storage = storage
        self.ingest = ingest
    }

    func capture() {
        guard !selecting else { return }
        selecting = true
        RegionSelector.select { [weak self] selection in
            guard let self else { return }
            self.selecting = false
            guard let (screen, rect) = selection, rect.width >= 4, rect.height >= 4 else { return }
            Task { await self.process(screen: screen, rect: rect) }
        }
    }

    private func process(screen: NSScreen, rect: CGRect) async {
        do {
            let cgImage = try await ScreenRecorder.captureScreenshot(screen: screen, rect: rect)
            guard let png = ImageProcessingService.pngData(cgImage) else { return }

            // 1. Immediately put on system pasteboard so user can ⌘V anywhere
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)

            // 2. Play subtle macOS camera shutter sound
            NSSound(named: "Tink")?.play()

            // 3. Save into ClipStick storage
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let title = "Screenshot \(f.string(from: Date()))"
            ingest.ingest(CaptureDraft(
                payload: .imageData(png),
                title: title,
                sourceApp: "ClipStick"
            ))

            onMessage?("Screenshot copied to clipboard! (⌘V)")
            onCaptured?()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't take screenshot"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            if case ScreenRecorder.RecorderError.permissionDenied = error {
                alert.addButton(withTitle: "Open System Settings")
            }
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
