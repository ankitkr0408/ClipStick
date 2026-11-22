import AppKit
import SwiftUI

struct ClipboardRootView: View {
    @ObservedObject var vm: ClipboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Dedicated top drag handle so the window can be moved intentionally
            WindowDragArea()
                .frame(height: 14)
                .overlay {
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 36, height: 4)
                }

            Group {
                if let editor = vm.editor {
                    MarkupEditorView(vm: editor, onSave: vm.saveEdit, onCancel: vm.cancelEdit)
                } else {
                    ClipboardBrowserView(vm: vm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: FloatingClipboardWindow.minWindowSize.width,
               maxWidth: .infinity,
               minHeight: FloatingClipboardWindow.minWindowSize.height,
               maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .overlay(alignment: .bottomTrailing) {
            ResizeCornerView()
                .frame(width: 16, height: 16)
                .padding(4)
        }
    }
}

/// Bottom-right corner resize grabber that lets the user fluidly resize the window
struct ResizeCornerView: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeCornerNSView { ResizeCornerNSView() }
    func updateNSView(_ nsView: ResizeCornerNSView, context: Context) {}

    final class ResizeCornerNSView: NSView {
        private var initialMouse: NSPoint = .zero
        private var initialFrame: NSRect = .zero

        override func resetCursorRects() {
            discardCursorRects()
            let cursor = NSCursor(image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil) ?? NSImage(), hotSpot: NSPoint(x: 8, y: 8))
            addCursorRect(bounds, cursor: cursor)
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.35))
            ctx.setLineWidth(1.2)
            // Two diagonal corner tick marks
            ctx.move(to: CGPoint(x: bounds.maxX - 4, y: bounds.maxY - 10))
            ctx.addLine(to: CGPoint(x: bounds.maxX - 10, y: bounds.maxY - 4))
            ctx.move(to: CGPoint(x: bounds.maxX - 4, y: bounds.maxY - 6))
            ctx.addLine(to: CGPoint(x: bounds.maxX - 6, y: bounds.maxY - 4))
            ctx.strokePath()
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            initialMouse = NSEvent.mouseLocation
            initialFrame = window.frame
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let current = NSEvent.mouseLocation
            let dx = current.x - initialMouse.x
            let dy = current.y - initialMouse.y

            let newWidth = max(window.minSize.width, initialFrame.width + dx)
            let newHeight = max(window.minSize.height, initialFrame.height - dy)
            let newY = initialFrame.maxY - newHeight

            window.setFrame(NSRect(x: initialFrame.origin.x, y: newY, width: newWidth, height: newHeight), display: true)
        }
    }
}

/// A transparent AppKit view that initiates native window dragging only when explicitly clicked.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView { DragNSView() }
    func updateNSView(_ nsView: DragNSView, context: Context) {}

    final class DragNSView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

struct ClipboardBrowserView: View {
    @ObservedObject var vm: ClipboardViewModel
    @FocusState private var searchFocused: Bool
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: ClipboardViewModel.columns)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .onAppear { searchFocused = true }
        .onChange(of: vm.showToken) { _, _ in searchFocused = true }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clips, text inside screenshots, apps…", text: $vm.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                if !vm.search.isEmpty {
                    Button { vm.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(ClipCategory.allCases) { cat in
                    Button { vm.category = cat } label: {
                        Label(cat.title, systemImage: cat.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(vm.category == cat ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.08)))
                            .foregroundStyle(vm.category == cat ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { vm.pickColor() } label: {
                    Label("Pick colour", systemImage: "eyedropper").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain).help("Pick any pixel on screen → copies HEX (⌥C anywhere)")
                if vm.category == .trash, vm.filtered.count > 0 {
                    Button("Empty Trash", role: .destructive) { vm.emptyTrash() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        let list = vm.filtered
        if list.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: vm.search.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text(vm.search.isEmpty ? "Nothing here yet — take a screenshot or copy something." : "No clips match “\(vm.search)”")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(list) { item in
                            ClipboardGridCard(
                                item: item, vm: vm,
                                isSelected: vm.selection.contains(item.id),
                                isFocused: vm.focusedID == item.id,
                                order: vm.selection.firstIndex(of: item.id).map { $0 + 1 },
                                selectionActive: !vm.selection.isEmpty)
                                .id(item.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: vm.focusedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if !vm.selection.isEmpty {
            BatchActionBar(vm: vm)
        } else {
            HStack(spacing: 14) {
                if let notice = vm.notice { Text(notice).foregroundStyle(.orange) }
                else {
                    hint("↩", "Copy"); hint("Click", "Image → edit"); hint("␣", "Select"); hint("⌘E", "Edit"); hint("⌘⌫", "Delete"); hint("esc", "Close")
                }
                Spacer()
                Text("\(vm.filtered.count) clips").foregroundStyle(.tertiary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
            Text(label).foregroundStyle(.secondary)
        }
    }
}
