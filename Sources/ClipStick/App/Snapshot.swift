import AppKit
import SwiftUI

/// `ClipStick --snapshot <dir>` — renders the HUD and the editor offscreen to PNGs (no screen-recording permission needed).
@MainActor
enum Snapshot {
    static func run(outputDir: String) -> Int32 {
        let out = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clipstick-snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        guard let storage = try? StorageService(rootURL: root) else { return 1 }

        let ingest = IngestService(storage: storage)
        ingest.ocrEnabled = { true }
        let shots = [
            fakeShot(["Network", "GET /api/users  500", "Internal Server Error"], bg: 0.12, fg: 1),
            fakeShot(["TableView.swift:42", "let row = rows[index]", "Fatal error: Index out of range"], bg: 1, fg: 0),
            fakeShot(["Sign in", "[ email@example.com ]", "[ •••••••••••• ]", "    Blank state"], bg: 0.93, fg: 0),
        ]
        for (i, s) in shots.enumerated() {
            ingest.ingest(CaptureDraft(payload: .imageData(ImageProcessingService.pngData(s)!),
                                       title: "Screenshot \(i + 1)", sourceApp: ["Chrome", "Xcode", "Simulator"][i],
                                       sourceBundleID: ["com.google.Chrome", "com.apple.dt.Xcode", "com.apple.iphonesimulator"][i]))
            ingest.drain()
        }
        ingest.ingest(CaptureDraft(payload: .text("Fatal error: Index out of range\nin TableView.swift:42\nat ViewController.viewDidLoad()"), sourceApp: "Terminal", sourceBundleID: "com.apple.Terminal"))
        ingest.ingest(CaptureDraft(payload: .text("https://github.com/anthropics/claude-code/issues/1"), sourceApp: "Safari", sourceBundleID: "com.apple.Safari"))
        ingest.drain()

        let monitor = PasteboardMonitor()
        let writer = ClipboardWriter(storage: storage, monitor: monitor)
        let vm = ClipboardViewModel(storage: storage, writer: writer, ingest: ingest)
        vm.focusedID = vm.filtered.first?.id
        let imgs = vm.items.filter { $0.kind == .image }.sorted { $0.createdAt < $1.createdAt }
        vm.toggleSelect(imgs[0]); vm.toggleSelect(imgs[1])

        render(ClipboardRootView(vm: vm), to: out.appendingPathComponent("hud-selection.png"))

        vm.clearSelection()
        vm.beginEdit(imgs[1])
        if let editor = vm.editor {
            editor.add(Annotation(kind: .rectangle, color: .red, points: [CGPoint(x: 0.05, y: 0.45), CGPoint(x: 0.75, y: 0.62)]))
            editor.add(Annotation(kind: .marker, color: .yellow, points: [CGPoint(x: 0.08, y: 0.76), CGPoint(x: 0.5, y: 0.77), CGPoint(x: 0.9, y: 0.76)]))
            editor.add(Annotation(kind: .arrow, color: .orange, points: [CGPoint(x: 0.85, y: 0.3), CGPoint(x: 0.6, y: 0.5)]))
            editor.add(Annotation(kind: .badge, color: .green, points: [CGPoint(x: 0.04, y: 0.2)], number: 1))
            editor.add(Annotation(kind: .text, color: .red, points: [CGPoint(x: 0.5, y: 0.1)], text: "Crash here", number: nil))
            editor.add(Annotation(kind: .pixelate, color: .red, points: [CGPoint(x: 0.1, y: 0.05), CGPoint(x: 0.35, y: 0.2)]))
            editor.setCrop(CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96))
            editor.tool = .crop
        }
        render(ClipboardRootView(vm: vm), to: out.appendingPathComponent("editor.png"))
        return 0
    }

    private static func render<V: View>(_ view: V, to url: URL) {
        let host = NSHostingView(rootView: view)
        let size = FloatingClipboardWindow.size
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))   // let async thumbnails load
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }

    private static func fakeShot(_ lines: [String], bg: CGFloat, fg: CGFloat) -> CGImage {
        let w = 900, h = 560
        let ctx = ImageProcessingService.makeContext(width: w, height: h, forceSRGB: true)!
        ctx.setFillColor(CGColor(gray: bg, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 34, weight: .regular),
                                                    .foregroundColor: NSColor(white: fg, alpha: 1)]
        for (i, l) in lines.enumerated() {
            AnnotationRenderer.drawText(l, at: CGPoint(x: 40, y: 60 + CGFloat(i) * 80), attributes: attrs, in: ctx)
        }
        return ctx.makeImage()!
    }
}
