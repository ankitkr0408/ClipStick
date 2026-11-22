import AppKit
import SwiftUI

/// State of one editing session: active tool, colour, edit state and undo/redo history.
@MainActor
final class AnnotationViewModel: ObservableObject {
    let item: ClipItem
    let image: CGImage
    /// Low-res copy of the image used to preview pixelation.
    let pixelated: CGImage?

    @Published private(set) var state: EditState
    @Published var tool: AnnotationTool = .rectangle
    @Published var color: AnnotationColor = .red
    @Published var cropAspect: CropAspect = .free

    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []

    /// Set by the canvas while its inline text field is open.
    var isTextEntryActive = false
    var textCancelHandler: (() -> Void)?

    init(item: ClipItem, image: CGImage, state: EditState) {
        self.item = item
        self.image = image
        self.state = state
        self.pixelated = ImageProcessingService.pixelationLayer(for: image)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var nextBadgeNumber: Int {
        (state.annotations.filter { $0.kind == .badge }.compactMap(\.number).max() ?? 0) + 1
    }

    func commit(_ new: EditState) {
        guard new != state else { return }
        undoStack.append(state)
        redoStack.removeAll()
        state = new
    }

    func add(_ annotation: Annotation) {
        var s = state
        s.annotations.append(annotation)
        commit(s)
    }

    func setCrop(_ rect: CGRect?) {
        var s = state
        // A "crop" covering essentially the whole image is no crop.
        if let r = rect, r.minX <= 0.002, r.minY <= 0.002, r.maxX >= 0.998, r.maxY >= 0.998 {
            s.crop = nil
        } else {
            s.crop = rect
        }
        commit(s)
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(state)
        state = prev
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
    }

    func clearAll() { commit(EditState()) }
}
