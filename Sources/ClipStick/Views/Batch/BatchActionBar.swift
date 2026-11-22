import AppKit
import SwiftUI

struct BatchActionBar: View {
    @ObservedObject var vm: ClipboardViewModel
    @AppStorage(Preferences.Key.stitchSpacing) private var stitchSpacing = true

    var body: some View {
        let images = vm.selectedImages.count
        let dragURLs = vm.selectedItems.filter { [.image, .file, .video].contains($0.kind) }.count

        HStack(spacing: 8) {
            Text("\(vm.selection.count) selected").font(.system(size: 12, weight: .semibold))
            Button { vm.clearSelection() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear selection")

            Spacer()
            if let notice = vm.notice { Text(notice).font(.system(size: 11)).foregroundStyle(.orange) }

            Menu {
                Button("Stitch Vertically") { vm.stitch(.vertical) }
                Button("Stitch Horizontally") { vm.stitch(.horizontal) }
                Divider()
                Toggle("Divider spacing", isOn: $stitchSpacing)
            } label: {
                Label("Stitch (\(images))", systemImage: "rectangle.split.1x2")
            }
            .menuStyle(.borderedButton)
            .fixedSize()
            .disabled(images < 2)
            .help("Merge selected screenshots into one image, in the order you selected them")

            Button { vm.copyForAI() } label: { Label("Copy for AI", systemImage: "sparkles") }
                .help("Markdown context + screenshots, ready for Claude / GitHub")
            Button { vm.copyAll() } label: { Label("Copy All", systemImage: "doc.on.doc") }

            if dragURLs > 0 {
                Label("Drag \(dragURLs)", systemImage: "square.and.arrow.up.on.square")
                    .font(.system(size: 12))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3])))
                    .overlay(MultiFileDragSource { vm.selectionExportURLs() })
                    .help("Drag all selected files into a browser, chat or Finder")
            }

            Button(role: .destructive) { vm.deleteSelectionOrFocused() } label: { Label("Delete", systemImage: "trash") }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .frame(height: 40)
    }
}

/// Transparent overlay that starts a native multi-file drag (SwiftUI's `onDrag` only carries one item).
struct MultiFileDragSource: NSViewRepresentable {
    let urls: () -> [URL]

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView()
        v.provider = urls
        return v
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) { nsView.provider = urls }

    final class DragSourceView: NSView, NSDraggingSource {
        var provider: (() -> [URL])?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDragged(with event: NSEvent) {
            guard let urls = provider?(), !urls.isEmpty else { return }
            let local = convert(event.locationInWindow, from: nil)
            let items = urls.enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let offset = CGFloat(min(index, 4)) * 6
                item.setDraggingFrame(NSRect(x: local.x - 28 + offset, y: local.y - 28 - offset, width: 56, height: 56),
                                      contents: NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    }
}
