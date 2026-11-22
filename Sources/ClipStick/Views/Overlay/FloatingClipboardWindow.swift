import AppKit
import SwiftUI

/// Borderless, non-activating HUD panel: it takes keyboard focus without stealing activation from the
/// app you were working in, so the paste lands where you expect.
final class FloatingClipboardWindow: NSPanel {
    static let defaultSize = NSSize(width: 900, height: 600)
    static let size = defaultSize
    static let minWindowSize = NSSize(width: 640, height: 420)
    private static let sizeKey = "FloatingClipboardWindow.userSize"

    init() {
        let savedWidth = UserDefaults.standard.double(forKey: "\(Self.sizeKey).width")
        let savedHeight = UserDefaults.standard.double(forKey: "\(Self.sizeKey).height")
        let initialSize: NSSize
        if savedWidth >= Self.minWindowSize.width && savedHeight >= Self.minWindowSize.height {
            initialSize = NSSize(width: savedWidth, height: savedHeight)
        } else {
            initialSize = Self.defaultSize
        }

        super.init(contentRect: NSRect(origin: .zero, size: initialSize),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        minSize = Self.minWindowSize
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResize), name: NSWindow.didResizeNotification, object: self)
    }

    @objc private func windowDidResize() {
        guard frame.width >= Self.minWindowSize.width && frame.height >= Self.minWindowSize.height else { return }
        UserDefaults.standard.set(frame.width, forKey: "\(Self.sizeKey).width")
        UserDefaults.standard.set(frame.height, forKey: "\(Self.sizeKey).height")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardWindowController: NSObject {
    private let panel = FloatingClipboardWindow()
    private let vm: ClipboardViewModel
    private var keyMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init(vm: ClipboardViewModel) {
        self.vm = vm
        super.init()
        let host = NSHostingView(rootView: ClipboardRootView(vm: vm))
        host.autoresizingMask = [.width, .height]
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = host

        vm.onDismiss = { [weak self] in self?.hide() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey), name: NSWindow.didResignKeyNotification, object: panel)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return MainActor.assumeIsolated { self.vm.handleKeyDown(event) } ? nil : event
        }
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        vm.prepareForShow()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                         y: frame.midY - size.height / 2 + frame.height * 0.06))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }

    @objc private func panelResignedKey() { hide() }
}
