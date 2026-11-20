import AppKit
import CoreGraphics

enum AnnotationTool: String, CaseIterable, Identifiable {
    case crop, marker, pen, arrow, rectangle, redact, pixelate, text, badge
    var id: String { rawValue }

    var title: String {
        switch self {
        case .crop: "Crop"
        case .marker: "Marker"
        case .pen: "Pen"
        case .arrow: "Arrow"
        case .rectangle: "Box"
        case .redact: "Redact"
        case .pixelate: "Pixelate"
        case .text: "Text"
        case .badge: "Step"
        }
    }

    var symbol: String {
        switch self {
        case .crop: "crop"
        case .marker: "highlighter"
        case .pen: "pencil.tip"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .redact: "eye.slash.fill"
        case .pixelate: "checkerboard.rectangle"
        case .text: "textformat"
        case .badge: "number.circle.fill"
        }
    }

    var hint: String {
        switch self {
        case .crop: "Drag to crop · handles resize · drag inside to move"
        case .marker: "Drag over code lines to highlight. Hold ⇧ for a straight line."
        case .pen: "Draw freehand. Hold ⇧ for a straight line."
        case .arrow: "Drag from the tail to the point of interest."
        case .rectangle: "Drag to outline a defect."
        case .redact: "Drag over secrets — painted solid black, unrecoverable."
        case .pixelate: "Drag to pixelate a region. Prefer Redact for tokens and keys."
        case .text: "Click to place a callout, then type. ↩ to confirm."
        case .badge: "Click to drop numbered step markers 1, 2, 3…"
        }
    }

    var annotationKind: Annotation.Kind? {
        switch self {
        case .crop: nil
        case .marker: .marker
        case .pen: .pen
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .redact: .redact
        case .pixelate: .pixelate
        case .text: .text
        case .badge: .badge
        }
    }
}

enum AnnotationColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, cyan
    var id: String { rawValue }

    private var components: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .red: (0.96, 0.22, 0.22)
        case .orange: (1.0, 0.58, 0.10)
        case .yellow: (1.0, 0.86, 0.10)
        case .green: (0.20, 0.78, 0.35)
        case .cyan: (0.10, 0.78, 0.95)
        }
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        let c = components
        return CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: alpha)
    }

    var nsColor: NSColor { NSColor(cgColor: cgColor())! }

    /// Legible foreground for text drawn on top of this colour.
    var onColor: NSColor {
        switch self {
        case .yellow, .cyan, .orange: NSColor(white: 0.08, alpha: 1)
        default: .white
        }
    }
}

/// One drawn mark. Coordinates are normalised (0…1) to the *original* image so the same
/// annotation renders identically in the editor and in the full-resolution export.
struct Annotation: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case pen, marker, arrow, rectangle, redact, pixelate, text, badge }

    var id = UUID()
    var kind: Kind
    var color: AnnotationColor
    var points: [CGPoint]
    var text: String?
    var number: Int?

    /// Rect spanned by the first two points (rectangle-like kinds), normalised.
    var rect: CGRect {
        guard points.count >= 2 else { return .zero }
        let a = points[0], b = points[1]
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// Everything the editor changes about a clip. The original image blob is never touched.
struct EditState: Codable, Hashable {
    var annotations: [Annotation] = []
    /// Normalised crop rectangle; nil = uncropped.
    var crop: CGRect?

    var isEmpty: Bool { annotations.isEmpty && crop == nil }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free, square, fourThree, sixteenNine, threeTwo
    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Free"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .sixteenNine: "16:9"
        case .threeTwo: "3:2"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        case .threeTwo: 3.0 / 2.0
        }
    }
}
