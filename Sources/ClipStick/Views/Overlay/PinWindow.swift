import AppKit
import SwiftUI

/// Always-on-top, borderless sticky window showing a screenshot or text snippet. Click ✕ or press esc to close.
final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PinManager {
    static let shared = PinManager()
    private var panels: [PinPanel] = []

    func pin(image: NSImage) {
        let max: CGFloat = 420
        var size = image.size
        let scale = Swift.min(1, max / Swift.max(size.width, size.height))
        size = NSSize(width: Swift.max(120, size.width * scale), height: Swift.max(80, size.height * scale))
        show(AnyView(Image(nsImage: image).resizable().scaledToFit()), size: size)
    }

    func pin(text: String) {
        show(AnyView(ScrollView { Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10) }.background(.regularMaterial)),
             size: NSSize(width: 360, height: 240))
    }

    private func show(_ content: AnyView, size: NSSize) {
        let panel = PinPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel, .resizable],
                             backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Button { [weak panel] in if let panel { PinManager.shared.close(panel) } } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, .black.opacity(0.55))
                }.buttonStyle(.plain).padding(5).help("Unpin")
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25)))
        panel.contentView = NSHostingView(rootView: view)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(panels.count % 6) * 26
        panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24 - offset, y: screen.maxY - size.height - 24 - offset))
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    func close(_ panel: PinPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
    }
}
