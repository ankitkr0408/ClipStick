import AppKit
import SwiftUI

struct MarkupEditorView: View {
    @ObservedObject var vm: AnnotationViewModel
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ToolPaletteView(vm: vm, onSave: onSave, onCancel: onCancel)
            Divider().opacity(0.4)
            AnnotationCanvas(vm: vm)
                .background(Color.black.opacity(0.18))
            Divider().opacity(0.4)
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(vm.tool.hint).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if vm.tool == .crop {
                Picker("Aspect", selection: $vm.cropAspect) {
                    ForEach(CropAspect.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                Button("Reset Crop") { vm.setCrop(nil) }.disabled(vm.state.crop == nil)
            }
            Button("Clear All") { vm.clearAll() }.disabled(vm.state.isEmpty).help("Removes all edits. The original screenshot is never modified.")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var vm: AnnotationViewModel

    func makeNSView(context: Context) -> AnnotationCanvasView { AnnotationCanvasView(vm: vm) }

    func updateNSView(_ view: AnnotationCanvasView, context: Context) {
        view.vm = vm
        view.refresh()
    }
}

/// Flipped (top-left origin) view: draws the image + annotations via the shared renderer and
/// turns mouse input into normalised annotations / crop changes.
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    var vm: AnnotationViewModel

    private var inProgress: Annotation?
    private var liveCrop: CGRect?
    private var cropMode: CropMode?
    private var textField: NSTextField?
    private var textAnchor = CGPoint.zero
    private var textColor = AnnotationColor.red

    private struct Handle: Equatable { var hx: Int; var hy: Int }   // -1 / 0 / 1 = left|none|right, top|none|bottom
    private enum CropMode {
        case fresh(anchor: CGPoint)
        case move(offset: CGPoint, size: CGSize)
        case resize(Handle, original: CGRect)
    }

    init(vm: AnnotationViewModel) {
        self.vm = vm
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsDisplay = true }

    func refresh() {
        if vm.tool != .text { commitText() }
        needsDisplay = true
    }

    // MARK: Geometry

    private var fit: CGRect {
        let img = CGSize(width: vm.image.width, height: vm.image.height)
        let avail = bounds.insetBy(dx: 20, dy: 16)
        guard avail.width > 0, avail.height > 0, img.width > 0, img.height > 0 else { return .zero }
        let s = min(avail.width / img.width, avail.height / img.height)
        let w = img.width * s, h = img.height * s
        return CGRect(x: avail.midX - w / 2, y: avail.midY - h / 2, width: w, height: h)
    }

    private func norm(_ p: CGPoint) -> CGPoint {
        let f = fit
        return CGPoint(x: min(max((p.x - f.minX) / f.width, 0), 1), y: min(max((p.y - f.minY) / f.height, 0), 1))
    }

    private func clampToFit(_ p: CGPoint) -> CGPoint {
        let f = fit
        return CGPoint(x: min(max(p.x, f.minX), f.maxX), y: min(max(p.y, f.minY), f.maxY))
    }

    private func toView(_ r: CGRect) -> CGRect {
        let f = fit
        return CGRect(x: f.minX + r.minX * f.width, y: f.minY + r.minY * f.height, width: r.width * f.width, height: r.height * f.height)
    }

    private var cropInView: CGRect? {
        if let liveCrop { return liveCrop }
        if let crop = vm.state.crop { return toView(crop) }
        if vm.tool == .crop { return fit }
        return nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let f = fit
        guard f.width > 0 else { return }

        ctx.saveGState()
        ctx.translateBy(x: f.minX, y: f.minY)
        AnnotationRenderer.drawImage(vm.image, in: CGRect(origin: .zero, size: f.size), ctx)
        var all = vm.state.annotations
        if let inProgress { all.append(inProgress) }
        AnnotationRenderer.draw(all, size: f.size, pixelated: vm.pixelated, in: ctx)
        ctx.restoreGState()

        if let crop = cropInView {
            // Dim everything outside the crop (stronger while the crop tool is active).
            ctx.saveGState()
            ctx.addRect(f)
            ctx.addRect(crop)
            ctx.setFillColor(CGColor(gray: 0, alpha: vm.tool == .crop ? 0.55 : 0.35))
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()

            if vm.tool == .crop {
                // Rule-of-thirds grid lines
                ctx.saveGState()
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
                ctx.setLineWidth(1)
                let w3 = crop.width / 3, h3 = crop.height / 3
                ctx.move(to: CGPoint(x: crop.minX + w3, y: crop.minY))
                ctx.addLine(to: CGPoint(x: crop.minX + w3, y: crop.maxY))
                ctx.move(to: CGPoint(x: crop.minX + 2 * w3, y: crop.minY))
                ctx.addLine(to: CGPoint(x: crop.minX + 2 * w3, y: crop.maxY))
                ctx.move(to: CGPoint(x: crop.minX, y: crop.minY + h3))
                ctx.addLine(to: CGPoint(x: crop.maxX, y: crop.minY + h3))
                ctx.move(to: CGPoint(x: crop.minX, y: crop.minY + 2 * h3))
                ctx.addLine(to: CGPoint(x: crop.maxX, y: crop.minY + 2 * h3))
                ctx.strokePath()
                ctx.restoreGState()

                // Border outline
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
                ctx.setLineWidth(2)
                ctx.stroke(crop)

                // Handles (12x12 white squares with border and drop shadow)
                for h in Self.allHandles {
                    let c = handlePoint(h, in: crop)
                    let r = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
                    ctx.saveGState()
                    ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(gray: 0, alpha: 0.5))
                    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                    ctx.fill(r)
                    ctx.restoreGState()

                    ctx.setStrokeColor(CGColor(gray: 0.2, alpha: 0.8))
                    ctx.setLineWidth(1)
                    ctx.stroke(r)
                }
            }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        commitText()
        let p = convert(event.locationInWindow, from: nil)
        let inside = fit.insetBy(dx: -6, dy: -6).contains(p)

        switch vm.tool {
        case .crop:
            beginCrop(at: p)
        case .marker, .pen:
            guard inside else { return }
            inProgress = Annotation(kind: vm.tool == .pen ? .pen : .marker, color: vm.color, points: [norm(p)])
        case .arrow, .rectangle, .redact, .pixelate:
            guard inside, let kind = vm.tool.annotationKind else { return }
            let n = norm(p)
            inProgress = Annotation(kind: kind, color: vm.color, points: [n, n])
        case .badge:
            guard inside else { return }
            vm.add(Annotation(kind: .badge, color: vm.color, points: [norm(p)], number: vm.nextBadgeNumber))
        case .text:
            guard inside else { return }
            beginText(at: p)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if vm.tool == .crop { updateCrop(to: p); needsDisplay = true; return }
        guard var a = inProgress else { return }
        let n = norm(p)
        let f = fit
        switch a.kind {
        case .pen, .marker:
            if event.modifierFlags.contains(.shift) {
                a.points = [a.points[0], n]
            } else if let last = a.points.last, hypot((n.x - last.x) * f.width, (n.y - last.y) * f.height) > 1.5 {
                a.points.append(n)
            }
        default:
            a.points[1] = n
        }
        inProgress = a
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if vm.tool == .crop { endCrop(); return }
        guard let a = inProgress else { return }
        inProgress = nil
        let f = fit
        let keep: Bool
        switch a.kind {
        case .pen: keep = true
        case .marker: keep = a.points.count >= 2
        case .arrow:
            keep = hypot((a.points[1].x - a.points[0].x) * f.width, (a.points[1].y - a.points[0].y) * f.height) >= 6
        default:
            keep = a.rect.width * f.width >= 4 && a.rect.height * f.height >= 4
        }
        if keep { vm.add(a) }
        needsDisplay = true
    }

    // MARK: Crop

    private static let allHandles: [Handle] = [
        Handle(hx: -1, hy: -1), Handle(hx: 1, hy: -1), Handle(hx: -1, hy: 1), Handle(hx: 1, hy: 1),   // corners first
        Handle(hx: 0, hy: -1), Handle(hx: 0, hy: 1), Handle(hx: -1, hy: 0), Handle(hx: 1, hy: 0),
    ]

    private func handlePoint(_ h: Handle, in r: CGRect) -> CGPoint {
        CGPoint(x: h.hx < 0 ? r.minX : (h.hx > 0 ? r.maxX : r.midX), y: h.hy < 0 ? r.minY : (h.hy > 0 ? r.maxY : r.midY))
    }

    private func handleHit(_ r: CGRect, _ p: CGPoint) -> Handle? {
        let threshold: CGFloat = 20
        return Self.allHandles.first { h in
            let c = handlePoint(h, in: r)
            return abs(c.x - p.x) <= threshold && abs(c.y - p.y) <= threshold
        }
    }

    private func beginCrop(at raw: CGPoint) {
        let p = clampToFit(raw)
        if let r = cropInView {
            if let h = handleHit(r, p) { cropMode = .resize(h, original: r); liveCrop = r; return }
            if r.contains(p) { cropMode = .move(offset: CGPoint(x: p.x - r.minX, y: p.y - r.minY), size: r.size); liveCrop = r; return }
        }
        cropMode = .fresh(anchor: p)
    }

    private func updateCrop(to raw: CGPoint) {
        let f = fit
        let p = clampToFit(raw)
        let ratio = vm.cropAspect.ratio
        switch cropMode {
        case .fresh(let anchor):
            if hypot(p.x - anchor.x, p.y - anchor.y) >= 6 {
                liveCrop = Self.lockedRect(anchor: anchor, pointer: p, ratio: ratio, bounds: f)
            }
        case .move(let off, let size):
            let ox = min(max(p.x - off.x, f.minX), f.maxX - size.width)
            let oy = min(max(p.y - off.y, f.minY), f.maxY - size.height)
            liveCrop = CGRect(origin: CGPoint(x: ox, y: oy), size: size)
        case .resize(let h, let orig):
            if h.hx != 0 && h.hy != 0 {
                let anchor = CGPoint(x: h.hx < 0 ? orig.maxX : orig.minX, y: h.hy < 0 ? orig.maxY : orig.minY)
                liveCrop = Self.lockedRect(anchor: anchor, pointer: p, ratio: ratio, bounds: f)
            } else {
                var r = orig
                if h.hx < 0 { r.origin.x = min(p.x, orig.maxX - 8); r.size.width = orig.maxX - r.origin.x }
                if h.hx > 0 { r.size.width = max(p.x - orig.minX, 8) }
                if h.hy < 0 { r.origin.y = min(p.y, orig.maxY - 8); r.size.height = orig.maxY - r.origin.y }
                if h.hy > 0 { r.size.height = max(p.y - orig.minY, 8) }
                liveCrop = r.intersection(f)
            }
        case nil: break
        }
    }

    private func endCrop() {
        defer { cropMode = nil; liveCrop = nil; needsDisplay = true }
        let f = fit
        guard let r = liveCrop, r.width >= 8, r.height >= 8, f.width > 0 else { return }
        vm.setCrop(CGRect(x: (r.minX - f.minX) / f.width, y: (r.minY - f.minY) / f.height,
                          width: r.width / f.width, height: r.height / f.height))
    }

    /// Rectangle spanned by `anchor` and `pointer`, optionally locked to an aspect ratio and kept inside `bounds`.
    static func lockedRect(anchor: CGPoint, pointer: CGPoint, ratio: CGFloat?, bounds: CGRect) -> CGRect {
        let dx = pointer.x - anchor.x, dy = pointer.y - anchor.y
        let sx: CGFloat = dx < 0 ? -1 : 1, sy: CGFloat = dy < 0 ? -1 : 1
        var w = abs(dx), h = abs(dy)
        if let ratio {
            if w / max(h, 0.001) > ratio { w = h * ratio } else { h = w / ratio }
        }
        let maxW = sx > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let maxH = sy > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        if w > maxW { w = maxW; if let ratio { h = w / ratio } }
        if h > maxH { h = maxH; if let ratio { w = h * ratio } }
        return CGRect(x: sx > 0 ? anchor.x : anchor.x - w, y: sy > 0 ? anchor.y : anchor.y - h, width: w, height: h)
    }

    // MARK: Text callouts

    private func beginText(at p: CGPoint) {
        let u = AnnotationRenderer.unit(for: fit.size)
        let size = max(11, 15 * u)
        let field = NSTextField(frame: NSRect(x: p.x, y: p.y, width: 240, height: size * 1.7))
        field.font = .systemFont(ofSize: size, weight: .bold)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = vm.color.nsColor
        field.textColor = vm.color.onColor
        field.focusRingType = .none
        field.placeholderString = "Text…"
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textAnchor = norm(p)
        textColor = vm.color
        vm.isTextEntryActive = true
        vm.textCancelHandler = { [weak self] in self?.cancelText() }
    }

    private func finishText(commit: Bool) {
        guard let field = textField else { return }
        textField = nil
        vm.isTextEntryActive = false
        vm.textCancelHandler = nil
        let s = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        if commit, !s.isEmpty {
            vm.add(Annotation(kind: .text, color: textColor, points: [textAnchor], text: s))
        }
        needsDisplay = true
    }

    func commitText() { finishText(commit: true) }
    func cancelText() { finishText(commit: false) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): commitText(); return true
        case #selector(NSResponder.cancelOperation(_:)): cancelText(); return true
        default: return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }
}
