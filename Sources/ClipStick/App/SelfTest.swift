import AppKit

/// `ClipStick --selftest` — headless checks for storage, ingest/dedup, stitching, annotation rendering and OCR.
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func check(_ ok: Bool, _ name: String, _ detail: String = "") {
        print((ok ? "PASS" : "FAIL") + "  " + name + (detail.isEmpty ? "" : "  — \(detail)"))
        if !ok { failures += 1 }
    }

    static func run() -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clipstick-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        // --- Storage + ingest + dedup
        guard let storage = try? StorageService(rootURL: root) else { print("FAIL  storage init"); return 1 }
        let ingest = IngestService(storage: storage)
        ingest.ocrEnabled = { true }
        let red = solid(200, 100, r: 1, g: 0, b: 0)
        let blue = solid(100, 200, r: 0, g: 0, b: 1)
        let redPNG = ImageProcessingService.pngData(red)!
        let redTIFF = NSImage(cgImage: red, size: .zero).tiffRepresentation!

        ingest.ingest(CaptureDraft(payload: .imageData(redPNG), sourceApp: "Test"))
        ingest.ingest(CaptureDraft(payload: .imageData(redTIFF), sourceApp: "Test"))   // same pixels, different encoding
        ingest.ingest(CaptureDraft(payload: .imageData(ImageProcessingService.pngData(blue)!)))
        ingest.ingest(CaptureDraft(payload: .text("Fatal error: Index out of range in TableView.swift:42\nsecond line")))
        ingest.ingest(CaptureDraft(payload: .text("Fatal error: Index out of range in TableView.swift:42\nsecond line")))
        ingest.ingest(CaptureDraft(payload: .text("https://example.com/path")))
        ingest.ingest(CaptureDraft(payload: .text("   \n ")))
        ingest.drain()
        let all = storage.fetchAll()
        check(all.count == 4, "ingest dedups image (png vs tiff) and text, ignores blanks", "got \(all.count) clips")
        check(all.filter { $0.kind == .image }.count == 2, "two distinct images stored")
        check(all.contains { $0.kind == .url }, "URL clip detected")
        if let img = all.first(where: { $0.kind == .image }) {
            check(FileManager.default.fileExists(atPath: storage.blobURL(img.blobName!).path), "blob written")
            check(FileManager.default.fileExists(atPath: storage.thumbURL(img.thumbName!).path), "thumbnail written")
            check(img.pixelWidth > 0, "pixel size recorded")
        }

        // --- Stitch
        let v = ImageProcessingService.stitch([red, blue], direction: .vertical, spacing: 10)
        check(v?.width == 200 && v?.height == 100 + 400 + 10, "vertical stitch scales to widest + spacing", "\(v?.width ?? 0)x\(v?.height ?? 0)")
        let h = ImageProcessingService.stitch([red, blue], direction: .horizontal, spacing: 0)
        check(h?.height == 200 && h?.width == 400 + 100, "horizontal stitch scales to tallest", "\(h?.width ?? 0)x\(h?.height ?? 0)")
        if let v, let px = pixel(v, x: 100, y: 10) { check(px.r > 200 && px.b < 50, "vertical stitch: first image on top (red)") }
        if let v, let px = pixel(v, x: 100, y: v.height - 10) { check(px.b > 200 && px.r < 50, "vertical stitch: second image below (blue)") }

        // --- Render: redact + crop (normalised coordinates, y-down)
        let canvas = solid(400, 200, r: 1, g: 1, b: 1)
        let redact = Annotation(kind: .redact, color: .red, points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.5)])
        let state = EditState(annotations: [redact], crop: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        let out = ImageProcessingService.render(original: canvas, state: state)
        check(out?.width == 200 && out?.height == 200, "crop applied", "\(out?.width ?? 0)x\(out?.height ?? 0)")
        if let out {
            let topLeft = pixel(out, x: 20, y: 20), bottomLeft = pixel(out, x: 20, y: 180)
            check((topLeft?.r ?? 255) < 10, "redact paints top-left black (y-down space correct)")
            check((bottomLeft?.r ?? 0) > 245, "area outside redact untouched")
        }
        let big = solid(1200, 600, r: 1, g: 1, b: 1)   // unit == 1, so strokes are 4px / badge radius 13px
        let arrow = Annotation(kind: .arrow, color: .green, points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)])
        let badge = Annotation(kind: .badge, color: .orange, points: [CGPoint(x: 0.5, y: 0.2)], number: 3)
        let text = Annotation(kind: .text, color: .cyan, points: [CGPoint(x: 0.1, y: 0.7)], text: "Here", number: nil)
        let multi = ImageProcessingService.render(original: big, state: EditState(annotations: [arrow, badge, text], crop: nil))
        check(multi?.width == 1200, "arrow/badge/text render without crop")
        if let multi, let p = pixel(multi, x: 600, y: 300) { check(p.g > p.r + 80 && p.g > 150, "arrow shaft drawn at mid-height", "rgb \(p.r),\(p.g),\(p.b)") }
        if let multi, let p = pixel(multi, x: 609, y: 120) { check(p.r > 240 && p.g > 120 && p.g < 190 && p.b < 60, "badge fill (orange) drawn at (0.5, 0.2)", "rgb \(p.r),\(p.g),\(p.b)") }
        if let multi, let p = pixel(multi, x: 120 + 4, y: 420 + 4) { check(p.b > 200 && p.r < 60, "text callout background (cyan) drawn at (0.1, 0.7)", "rgb \(p.r),\(p.g),\(p.b)") }

        // Test square, circle, triangle rendering
        let square = Annotation(kind: .square, color: .red, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.4)])
        let circle = Annotation(kind: .circle, color: .green, points: [CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.8, y: 0.4)])
        let triangle = Annotation(kind: .triangle, color: .orange, points: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.6, y: 0.9)])
        let shapesRendered = ImageProcessingService.render(original: big, state: EditState(annotations: [square, circle, triangle], crop: nil))
        check(shapesRendered != nil, "square, circle, triangle render successfully")

        let json = try? JSONEncoder().encode(state)
        check(json.flatMap { try? JSONDecoder().decode(EditState.self, from: $0) } == state, "EditState JSON round-trip")

        // --- OCR
        let code = textImage(["func load() {", "    let x = items[42]", "    print(x)", "}"])
        let recognised = OCRService.recognize(code) ?? ""
        check(recognised.contains("items[42]") || recognised.contains("items"), "Vision OCR reads rendered code", recognised.replacingOccurrences(of: "\n", with: " ⏎ "))
        check(recognised.contains("\n") && recognised.split(separator: "\n").contains { $0.hasPrefix("  ") }, "OCR keeps indentation", recognised.replacingOccurrences(of: "\n", with: " ⏎ "))

        // --- Prune
        let removed = storage.prune(maxItems: 1)
        check(removed.count == all.count - 1, "prune keeps newest N non-favourites", "removed \(removed.count)")

        print(failures == 0 ? "\nAll self-tests passed." : "\n\(failures) self-test(s) FAILED.")
        return failures == 0 ? 0 : 1
    }

    // MARK: Helpers

    private static func solid(_ w: Int, _ h: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        let ctx = ImageProcessingService.makeContext(width: w, height: h, forceSRGB: true)!
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// Pixel at top-left-origin coordinates, 0…255.
    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
        guard let ctx = ImageProcessingService.makeContext(width: image.width, height: image.height, forceSRGB: true),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let row = image.height - 1 - y   // bitmap memory is stored top row first, so index directly instead
        _ = row
        let p = data.assumingMemoryBound(to: UInt8.self)
        let o = y * ctx.bytesPerRow + x * 4
        // premultipliedFirst, little-endian host order handled by CGContext default: bytes are A R G B
        return (Int(p[o + 1]), Int(p[o + 2]), Int(p[o + 3]))
    }

    private static func textImage(_ lines: [String]) -> CGImage {
        let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let lineH: CGFloat = 40
        let w = 700, h = Int(lineH) * lines.count + 40
        let ctx = ImageProcessingService.makeContext(width: w, height: h, forceSRGB: true)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        for (i, line) in lines.enumerated() {
            AnnotationRenderer.drawText(line, at: CGPoint(x: 20, y: 20 + CGFloat(i) * lineH), attributes: attrs, in: ctx)
        }
        return ctx.makeImage()!
    }
}
