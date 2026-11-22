import AppKit
import SwiftUI

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published var search = ""
    @Published var category: ClipCategory = .all
    /// Ordered by click order — the order used when stitching.
    @Published private(set) var selection: [UUID] = []
    @Published var focusedID: UUID?
    @Published var editor: AnnotationViewModel?
    @Published var notice: String?
    /// Bumped every time the HUD is shown so the view can refocus the search field.
    @Published private(set) var showToken = 0

    let storage: StorageService
    let writer: ClipboardWriter
    let ingest: IngestService
    var onDismiss: (() -> Void)?

    static let columns = 4
    private var anchorID: UUID?

    init(storage: StorageService, writer: ClipboardWriter, ingest: IngestService) {
        self.storage = storage
        self.writer = writer
        self.ingest = ingest
        items = storage.fetchAll()
    }

    // MARK: Derived

    var filtered: [ClipItem] {
        let tokens = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            switch category {
            case .trash: guard item.isTrashed else { return false }
            case .favorites: guard item.isFavorite, !item.isTrashed else { return false }
            default:
                guard !item.isTrashed else { return false }
                if let kinds = category.kinds, !kinds.contains(item.kind) { return false }
            }
            guard !tokens.isEmpty else { return true }
            let hay = item.searchHaystack
            return tokens.allSatisfy { hay.contains($0) }
        }
    }

    var selectedItems: [ClipItem] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return selection.compactMap { byID[$0] }
    }

    var selectedImages: [ClipItem] { selectedItems.filter { $0.kind == .image } }
    var focusedItem: ClipItem? { focusedID.flatMap { id in items.first { $0.id == id } } }

    // MARK: Store sync

    func upsert(_ item: ClipItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        items.sort { $0.createdAt > $1.createdAt }
    }

    func remove(ids: [UUID]) {
        let set = Set(ids)
        items.removeAll { set.contains($0.id) }
        selection.removeAll { set.contains($0) }
    }

    func prepareForShow() {
        if editor == nil {
            search = ""
            selection = []
            focusedID = filtered.first?.id
        }
        showToken += 1
    }

    func dismiss() { onDismiss?() }

    // MARK: Selection

    func toggleSelect(_ item: ClipItem) {
        if let i = selection.firstIndex(of: item.id) { selection.remove(at: i) } else { selection.append(item.id) }
        anchorID = item.id
        focusedID = item.id
    }

    func rangeSelect(to item: ClipItem) {
        let list = filtered
        guard let to = list.firstIndex(where: { $0.id == item.id }) else { return }
        let from = anchorID.flatMap { a in list.firstIndex { $0.id == a } } ?? list.firstIndex { $0.id == focusedID } ?? to
        // The grid is newest-first; add the range oldest-first so stitching follows capture order.
        for clip in list[min(from, to)...max(from, to)].reversed() where !selection.contains(clip.id) {
            selection.append(clip.id)
        }
        focusedID = item.id
    }

    func selectAll() { selection = filtered.reversed().map(\.id) }
    func clearSelection() { selection = []; anchorID = nil }

    // MARK: Primary actions

    func activate(_ item: ClipItem) {
        let mods = NSEvent.modifierFlags
        focusedID = item.id
        if mods.contains(.command) { toggleSelect(item); return }
        if mods.contains(.shift) { rangeSelect(to: item); return }
        if !selection.isEmpty { toggleSelect(item); return }
        if item.isTrashed { return }
        if item.kind == .image { beginEdit(item) } else { copyAndDismiss(item) }
    }

    func copyAndDismiss(_ item: ClipItem) {
        writer.write([item])
        dismiss()
    }

    func copyOCR(_ item: ClipItem) {
        guard let text = item.ocrText, !text.isEmpty else { return }
        writer.writeText(text)
        dismiss()
    }

    func copyAll() {
        let list = selectedItems.isEmpty ? (focusedItem.map { [$0] } ?? []) : selectedItems
        guard !list.isEmpty else { return }
        writer.write(list)
        clearSelection()
        dismiss()
    }

    func copyForAI() {
        let list = selectedItems
        guard !list.isEmpty else { return }
        writer.writeAIBundle(list)
        clearSelection()
        dismiss()
    }

    func stitch(_ direction: StitchDirection) {
        let images = selectedImages
        guard images.count >= 2 else { notice = "Select at least two screenshots to stitch"; return }
        let urls = images.compactMap { $0.displayBlobName }.map { storage.blobURL($0) }
        let spacing = Preferences.stitchSpacing ? 12 : 0
        Task {
            let png = await Task.detached(priority: .userInitiated) { () -> Data? in
                let decoded = urls.compactMap { ImageProcessingService.cgImage(at: $0) }
                guard decoded.count >= 2 else { return nil }
                return ImageProcessingService.stitch(decoded, direction: direction, spacing: spacing)
                    .flatMap { ImageProcessingService.pngData($0) }
            }.value
            guard let png else { notice = "Could not stitch those images"; return }
            writer.writeImage(png: png)
            ingest.ingest(CaptureDraft(payload: .imageData(png), title: "Stitched · \(images.count) screenshots", sourceApp: "ClipStick"))
            clearSelection()
            dismiss()
        }
    }

    // MARK: Format / colour / pin

    func canFormat(_ item: ClipItem) -> Bool {
        [.text, .richText].contains(item.kind) && TextFormatter.format(item.text ?? "") != nil
    }

    func formatAndCopy(_ item: ClipItem) {
        guard let formatted = TextFormatter.format(item.text ?? "") else { return }
        writer.writeText(formatted)
        dismiss()
    }

    func copyPalette(_ item: ClipItem) {
        guard let name = item.blobName, let cg = ImageProcessingService.cgImage(at: storage.blobURL(name)) else { return }
        let colors = ColorService.palette(from: cg)
        guard !colors.isEmpty else { notice = "No colours found"; return }
        writer.writeText(colors.map(ColorService.hex).joined(separator: "\n"))
        notice = "Palette copied: " + colors.map(ColorService.hex).joined(separator: " ")
    }

    func pickColor() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            ColorService.pickFromScreen { color in
                guard let self, let color else { return }
                self.writer.writeText(ColorService.hex(color))
                self.notice = "\(ColorService.hex(color))  ·  \(ColorService.rgb(color))  ·  \(ColorService.hsl(color))"
            }
        }
    }

    func pin(_ item: ClipItem) {
        if item.kind == .image, let name = item.displayBlobName, let img = NSImage(contentsOf: storage.blobURL(name)) {
            PinManager.shared.pin(image: img)
        } else if let text = item.text ?? Optional(item.preview) {
            PinManager.shared.pin(text: text)
        }
        dismiss()
    }

    // MARK: Delete / favourite

    func deleteSelectionOrFocused() {
        let ids = selection.isEmpty ? (focusedID.map { [$0] } ?? []) : selection
        for id in ids { if let item = items.first(where: { $0.id == id }) { delete(item) } }
        clearSelection()
    }

    func delete(_ item: ClipItem) {
        if item.isTrashed {
            storage.delete(id: item.id)
            storage.removeFiles(for: item)
            remove(ids: [item.id])
        } else {
            var t = item
            t.deletedAt = Date()
            storage.save(t)
            upsert(t)
            selection.removeAll { $0 == item.id }
        }
        if focusedID == item.id { focusedID = filtered.first?.id }
    }

    func restore(_ item: ClipItem) {
        var r = item
        r.deletedAt = nil
        storage.save(r)
        upsert(r)
    }

    func toggleFavorite(_ item: ClipItem) {
        var f = item
        f.isFavorite.toggle()
        storage.save(f)
        upsert(f)
    }

    func emptyTrash() {
        for item in items where item.isTrashed { delete(item) }
    }

    // MARK: Editing

    func beginEdit(_ item: ClipItem) {
        guard item.kind == .image, let name = item.blobName,
              let cg = ImageProcessingService.cgImage(at: storage.blobURL(name)) else {
            notice = "Image file is missing"
            return
        }
        editor = AnnotationViewModel(item: item, image: cg, state: item.editState ?? EditState())
    }

    func cancelEdit() { editor = nil }

    /// Renders original + edits to a new PNG (original stays untouched), updates the clip, copies it, closes the HUD.
    func saveEdit() {
        guard let editor else { return }
        let item = editor.item, state = editor.state, original = editor.image
        self.editor = nil
        Task {
            let rendered = await Task.detached(priority: .userInitiated) { () -> (png: Data, thumb: Data?, size: CGSize)? in
                guard !state.isEmpty,
                      let cg = ImageProcessingService.render(original: original, state: state),
                      let png = ImageProcessingService.pngData(cg) else { return nil }
                let thumb = ImageProcessingService.resized(cg, maxPixel: 720).flatMap { ImageProcessingService.pngData($0) }
                return (png, thumb, CGSize(width: cg.width, height: cg.height))
            }.value
            finishEdit(item: item, state: state, rendered: rendered.map { ($0.png, $0.thumb) })
        }
    }

    private func finishEdit(item: ClipItem, state: EditState, rendered: (png: Data, thumb: Data?)?) {
        var updated = items.first { $0.id == item.id } ?? item
        let fm = FileManager.default
        if let old = updated.renderedBlobName { try? fm.removeItem(at: storage.blobURL(old)) }
        // The pristine thumbnail (`<id>.png`) is kept so clearing edits can fall back to it.
        let pristineThumb = "\(updated.id.uuidString).png"
        if let oldThumb = updated.thumbName, oldThumb != pristineThumb { try? fm.removeItem(at: storage.thumbURL(oldThumb)) }

        if let rendered {
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            let blobName = "\(updated.id.uuidString)-edit-\(stamp).png"
            try? rendered.png.write(to: storage.blobURL(blobName), options: .atomic)
            updated.renderedBlobName = blobName
            if let thumb = rendered.thumb {
                let thumbName = "\(updated.id.uuidString)-t\(stamp).png"
                try? thumb.write(to: storage.thumbURL(thumbName), options: .atomic)
                updated.thumbName = thumbName
            }
            updated.editStateJSON = (try? JSONEncoder().encode(state)).flatMap { String(data: $0, encoding: .utf8) }
        } else {
            // Edits cleared: fall back to the pristine original thumbnail.
            updated.renderedBlobName = nil
            updated.editStateJSON = nil
            if fm.fileExists(atPath: storage.thumbURL(pristineThumb).path) { updated.thumbName = pristineThumb }
        }
        storage.save(updated)
        upsert(updated)
        writer.write([updated])
        dismiss()
    }

    // MARK: Drag & drop

    func dragProvider(for item: ClipItem) -> NSItemProvider {
        switch item.kind {
        case .image, .file, .video:
            if let url = writer.exportFiles(for: [item]).first, let provider = NSItemProvider(contentsOf: url) { return provider }
            return NSItemProvider()
        default:
            return NSItemProvider(object: (item.text ?? item.preview) as NSString)
        }
    }

    /// Files for the multi-file drag handle in the batch bar.
    func selectionExportURLs() -> [URL] { writer.exportFiles(for: selectedItems) }

    // MARK: Keyboard (routed from the panel's local event monitor)

    func moveFocus(by delta: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        guard let current = list.firstIndex(where: { $0.id == focusedID }) else { focusedID = list.first?.id; return }
        focusedID = list[min(max(current + delta, 0), list.count - 1)].id
    }

    /// Returns true when the event was consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = Int(event.keyCode)
        let cmd = mods == .command

        if let editor {
            switch key {
            case 53: // esc
                if editor.isTextEntryActive { editor.textCancelHandler?() } else { cancelEdit() }
                return true
            case 36 where cmd, 76 where cmd: // ⌘↩
                saveEdit(); return true
            case 6 where (cmd || mods == [.command, .shift]) && !editor.isTextEntryActive: // ⌘Z / ⇧⌘Z
                if mods.contains(.shift) { editor.redo() } else { editor.undo() }
                return true
            default: return false
            }
        }

        switch key {
        case 53: // esc
            if !search.isEmpty { search = "" } else if !selection.isEmpty { clearSelection() } else { dismiss() }
            return true
        case 123 where mods.isEmpty: moveFocus(by: -1); return true
        case 124 where mods.isEmpty: moveFocus(by: 1); return true
        case 125 where mods.isEmpty: moveFocus(by: Self.columns); return true
        case 126 where mods.isEmpty: moveFocus(by: -Self.columns); return true
        case 36 where mods.isEmpty, 76 where mods.isEmpty: // return
            if selection.count > 1 { copyAll() } else if let item = focusedItem, !item.isTrashed { copyAndDismiss(item) }
            return true
        case 49 where mods.isEmpty && search.isEmpty: // space toggles selection
            if let item = focusedItem { toggleSelect(item) }
            return true
        case 0 where cmd && search.isEmpty: selectAll(); return true
        case 51 where cmd: deleteSelectionOrFocused(); return true
        case 14 where cmd: // ⌘E
            if let item = focusedItem, item.kind == .image { beginEdit(item) }
            return true
        default: return false
        }
    }
}
