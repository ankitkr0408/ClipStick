import AppKit

/// Full-screen crosshair overlay: drag to choose the area to record. Esc cancels.
@MainActor
final class RegionSelector {
    private static var current: RegionSelector?
    private var windows: [NSWindow] = []
    private var completion: ((NSScreen, CGRect)?) -> Void

    private init(completion: @escaping ((NSScreen, CGRect)?) -> Void) { self.completion = completion }

    /// `completion` receives the screen and the rect in global screen coordinates (bottom-left origin), or nil if cancelled.
    static func select(completion: @escaping ((NSScreen, CGRect)?) -> Void) {
        let selector = RegionSelector(completion: completion)
        current = selector
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onDone = { [weak selector] rect in selector?.finish(screen: screen, rect: rect) }
            w.contentView = view
            w.setFrame(screen.frame, display: true)
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(view)
            selector.windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(screen: NSScreen, rect: CGRect?) {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        Self.current = nil
        let result = rect.map { (screen, $0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)) }
        // Let the overlay disappear before capture starts so it never appears in the recording.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [completion] in completion(result) }
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onDone: ((CGRect?) -> Void)?
    private var start: NSPoint?
    private var rect: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let rect { dim.appendRect(rect); dim.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(rect == nil ? 0.15 : 0.45).setFill()
        dim.fill()
        guard let rect else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.stroke()
        let label = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attrs)
        let pill = NSRect(x: rect.minX, y: max(0, rect.minY - size.height - 10), width: size.width + 14, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        label.draw(at: NSPoint(x: pill.minX + 7, y: pill.minY + 3), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        rect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = convert(event.locationInWindow, from: nil)
        rect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(start.x - p.x), height: abs(start.y - p.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let rect, rect.width >= 48, rect.height >= 48 { onDone?(rect) } else { rect = nil; start = nil; needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDone?(nil) } else { super.keyDown(with: event) }
    }
}
