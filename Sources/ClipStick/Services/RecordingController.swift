import AppKit
import SwiftUI

/// Orchestrates "Record Bug Clip": select area → record (pill with timer + Stop) → MP4 + GIF → clip in the HUD.
@MainActor
final class RecordingController: ObservableObject {
    static let maxSeconds = 30

    @Published private(set) var elapsed = 0
    private let recorder = ScreenRecorder()
    private let storage: StorageService
    private let ingest: IngestService
    private var pill: NSPanel?
    private var timer: Timer?
    private var selecting = false
    /// Shown to the user in a HUD notice / alert.
    var onMessage: ((String) -> Void)?
    var onSaved: (() -> Void)?

    var isActive: Bool { recorder.isRecording || selecting }

    init(storage: StorageService, ingest: IngestService) {
        self.storage = storage
        self.ingest = ingest
        recorder.onUnexpectedStop = { [weak self] in Task { await self?.stop() } }
    }

    func toggle() {
        if recorder.isRecording { Task { await stop() } } else if !selecting { begin() }
    }

    private func begin() {
        selecting = true
        RegionSelector.select { [weak self] selection in
            guard let self else { return }
            self.selecting = false
            guard let (screen, rect) = selection else { return }
            Task { await self.startRecording(screen: screen, rect: rect) }
        }
    }

    private func startRecording(screen: NSScreen, rect: CGRect) async {
        do {
            try await recorder.start(screen: screen, rect: rect)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't start recording"
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
            return
        }
        elapsed = 0
        showPill(near: screen)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed += 1
                if self.elapsed >= Self.maxSeconds { Task { await self.stop() } }
            }
        }
    }

    func stop() async {
        guard recorder.isRecording else { return }
        timer?.invalidate(); timer = nil
        pill?.orderOut(nil); pill = nil
        let duration = recorder.startedAt.map { Date().timeIntervalSince($0) } ?? 0
        onMessage?("Processing clip…")
        do {
            let mp4 = try await recorder.stop()
            await finalize(mp4: mp4, duration: duration)
        } catch {
            onMessage?("Recording failed: \(error.localizedDescription)")
        }
    }

    private func finalize(mp4: URL, duration: TimeInterval) async {
        let id = UUID()
        let mp4Name = "\(id.uuidString).mp4", gifName = "\(id.uuidString).gif", posterName = "\(id.uuidString).png"
        let storage = self.storage
        let result = await Task.detached(priority: .userInitiated) { () -> ClipItem? in
            let fm = FileManager.default
            let mp4Dest = storage.blobURL(mp4Name)
            do { try fm.moveItem(at: mp4, to: mp4Dest) } catch { return nil }
            let gif = await GIFEncoder.encode(video: mp4Dest, output: storage.blobURL(gifName))
            if gif == nil { try? fm.removeItem(at: storage.blobURL(gifName)) }
            var posterSaved = false
            var w = 0, h = 0
            if let poster = await GIFEncoder.poster(video: mp4Dest), let png = ImageProcessingService.pngData(poster) {
                posterSaved = (try? png.write(to: storage.thumbURL(posterName), options: .atomic)) != nil
                w = poster.width; h = poster.height
            }
            let shareable = gif ?? mp4Dest
            let size = (try? shareable.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let secs = Int(duration.rounded())
            return ClipItem(
                id: id, kind: .video, preview: "Bug clip · \(secs)s", text: shareable.path,
                blobName: mp4Name, blobExt: "mp4", thumbName: posterSaved ? posterName : nil, filePath: shareable.path,
                byteSize: Int64(size), contentHash: IngestService.sha256("rec:" + id.uuidString), createdAt: Date(),
                sourceApp: "ClipStick", sessionID: nil, isFavorite: false, deletedAt: nil,
                renderedBlobName: gif == nil ? nil : gifName, pixelWidth: w, pixelHeight: h)
        }.value
        guard let item = result else { onMessage?("Couldn't save the recording"); return }
        ingest.insertRecording(item)
        let mb = String(format: "%.1f", Double(item.byteSize) / 1_000_000)
        onMessage?("Saved bug clip (\(item.renderedBlobName == nil ? "MP4" : "GIF"), \(mb) MB) — ↩ copy · ⌘⇧C markdown")
        onSaved?()
    }

    // MARK: Recording pill

    private func showPill(near screen: NSScreen) {
        let view = RecordingPill(controller: self) { [weak self] in Task { await self?.stop() } }
        let host = NSHostingView(rootView: view)
        let size = NSSize(width: 210, height: 38)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 12))
        panel.orderFrontRegardless()
        pill = panel
    }
}

private struct RecordingPill: View {
    @ObservedObject var controller: RecordingController
    let onStop: () -> Void
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 9, height: 9).opacity(pulse ? 0.35 : 1)
                .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
            Text(String(format: "%d:%02d / 0:%02d", controller.elapsed / 60, controller.elapsed % 60, RecordingController.maxSeconds))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Spacer(minLength: 0)
            Button(action: onStop) {
                Text("Stop").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color.red)).foregroundStyle(.white)
            }.buttonStyle(.plain).help("Stop (⌥R)")
        }
        .padding(.horizontal, 14)
        .frame(width: 210, height: 38)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
    }
}
