import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum StitchDirection: String { case vertical, horizontal }

/// Pure CoreGraphics image helpers: decode/encode, thumbnails, stitching, cropping and
/// flattening annotations. Safe to call from any thread.
enum ImageProcessingService {
    static let maxStitchDimension: Double = 16_000

    // MARK: Decode / encode

    static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func cgImage(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func isPNG(_ data: Data) -> Bool { data.starts(with: [0x89, 0x50, 0x4E, 0x47]) }

    static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func makeContext(width: Int, height: Int, like image: CGImage? = nil, forceSRGB: Bool = false) -> CGContext? {
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        if !forceSRGB, let cs = image?.colorSpace, cs.model == .rgb,
           let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: info) {
            return ctx
        }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: info)
    }

    /// SHA-256 of the sRGB pixels, so the same screenshot dedups whether it arrived as PNG, TIFF or a file.
    static func pixelHash(_ image: CGImage) -> String? {
        guard let ctx = makeContext(width: image.width, height: image.height, forceSRGB: true), let base = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = UnsafeRawBufferPointer(start: base, count: ctx.bytesPerRow * ctx.height)
        var hasher = SHA256()
        hasher.update(bufferPointer: bytes)
        hasher.update(data: Data("\(image.width)x\(image.height)".utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Scaling

    static func resized(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxPixel else { return image }
        let scale = Double(maxPixel) / Double(longest)
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        guard let ctx = makeContext(width: w, height: h, like: image) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Tiny version of the whole image; drawn back with interpolation off it becomes a pixelation layer.
    static func pixelationLayer(for image: CGImage, blocksOnLongSide: Int = 64) -> CGImage? {
        let scale = Double(blocksOnLongSide) / Double(max(image.width, image.height))
        guard scale < 1 else { return image }
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        guard let ctx = makeContext(width: w, height: h, like: image) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: Stitching

    /// Merges screenshots into one image. Vertical: all scaled to the widest width. Horizontal: all scaled to the tallest height.
    static func stitch(_ images: [CGImage], direction: StitchDirection, spacing: Int) -> CGImage? {
        guard let first = images.first else { return nil }
        let gap = Double(max(0, spacing))
        let sizes: [CGSize]
        switch direction {
        case .vertical:
            let w = Double(images.map(\.width).max()!)
            sizes = images.map { CGSize(width: w, height: (Double($0.height) * w / Double($0.width)).rounded()) }
        case .horizontal:
            let h = Double(images.map(\.height).max()!)
            sizes = images.map { CGSize(width: (Double($0.width) * h / Double($0.height)).rounded(), height: h) }
        }
        let gaps = gap * Double(images.count - 1)
        var totalW: Double, totalH: Double
        switch direction {
        case .vertical:
            totalW = sizes[0].width
            totalH = sizes.reduce(0) { $0 + $1.height } + gaps
        case .horizontal:
            totalW = sizes.reduce(0) { $0 + $1.width } + gaps
            totalH = sizes[0].height
        }
        let f = min(1, maxStitchDimension / max(totalW, totalH))
        totalW *= f; totalH *= f
        let W = Int(totalW.rounded()), H = Int(totalH.rounded())
        guard let ctx = makeContext(width: W, height: H, like: first) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.interpolationQuality = .high

        var offset = 0.0
        for (image, size) in zip(images, sizes) {
            let w = size.width * f, h = size.height * f
            switch direction {
            case .vertical:
                ctx.draw(image, in: CGRect(x: 0, y: Double(H) - offset - h, width: w, height: h))
                offset += h + gap * f
            case .horizontal:
                ctx.draw(image, in: CGRect(x: offset, y: 0, width: w, height: h))
                offset += w + gap * f
            }
        }
        return ctx.makeImage()
    }

    // MARK: Crop + annotate

    /// Flattens annotations onto the original, then applies the crop. The original is not modified.
    static func render(original: CGImage, state: EditState) -> CGImage? {
        let w = original.width, h = original.height
        var result = original
        if !state.annotations.isEmpty {
            guard let ctx = makeContext(width: w, height: h, like: original) else { return nil }
            ctx.draw(original, in: CGRect(x: 0, y: 0, width: w, height: h))
            // Switch to a top-left origin (y down), the space the renderer works in.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            let layer = state.annotations.contains { $0.kind == .pixelate } ? pixelationLayer(for: original) : nil
            AnnotationRenderer.draw(state.annotations, size: CGSize(width: w, height: h), pixelated: layer, in: ctx)
            guard let flat = ctx.makeImage() else { return nil }
            result = flat
        }
        if let crop = state.crop {
            let rect = CGRect(x: crop.minX * Double(w), y: crop.minY * Double(h),
                              width: crop.width * Double(w), height: crop.height * Double(h))
                .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
            if rect.width >= 1, rect.height >= 1, let cropped = result.cropping(to: rect) { result = cropped }
        }
        return result
    }
}

/// Draws annotations in a **top-left-origin** coordinate space of the given size.
/// The editor canvas (flipped NSView) and the exporter (flipped bitmap context) share this code, so
/// what you see is what you paste. Stroke sizes scale with the image so they look the same at any resolution.
enum AnnotationRenderer {
    static func unit(for size: CGSize) -> CGFloat { max(size.width, size.height) / 1200 }

    /// Draws a CGImage upright into a y-down context.
    static func drawImage(_ image: CGImage, in rect: CGRect, _ ctx: CGContext, interpolation: CGInterpolationQuality = .high) {
        ctx.saveGState()
        ctx.interpolationQuality = interpolation
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    static func draw(_ annotations: [Annotation], size: CGSize, pixelated: CGImage?, in ctx: CGContext) {
        let u = unit(for: size)
        for a in annotations { draw(a, size: size, unit: u, pixelated: pixelated, in: ctx) }
    }

    static func draw(_ a: Annotation, size: CGSize, unit u: CGFloat, pixelated: CGImage?, in ctx: CGContext) {
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        func scaled(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
        }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch a.kind {
        case .pen, .marker:
            guard let first = a.points.first else { return }
            let path = CGMutablePath()
            path.move(to: pt(first))
            if a.points.count == 1 { path.addLine(to: pt(first)) }
            for p in a.points.dropFirst() { path.addLine(to: pt(p)) }
            ctx.addPath(path)
            ctx.setLineJoin(.round)
            if a.kind == .marker {
                ctx.setLineCap(.butt)
                ctx.setLineWidth(22 * u)
                ctx.setStrokeColor(a.color.cgColor(alpha: 0.4))
            } else {
                ctx.setLineCap(.round)
                ctx.setLineWidth(4 * u)
                ctx.setStrokeColor(a.color.cgColor())
            }
            ctx.strokePath()

        case .arrow:
            guard a.points.count >= 2 else { return }
            let p0 = pt(a.points[0]), p1 = pt(a.points[1])
            let len = hypot(p1.x - p0.x, p1.y - p0.y)
            guard len > 2 else { return }
            let angle = atan2(p1.y - p0.y, p1.x - p0.x)
            let headLen = min(len * 0.6, 22 * u)
            let spread = CGFloat.pi / 7
            let base = CGPoint(x: p1.x - cos(angle) * headLen * 0.8, y: p1.y - sin(angle) * headLen * 0.8)
            ctx.setStrokeColor(a.color.cgColor())
            ctx.setLineWidth(4 * u)
            ctx.setLineCap(.butt)
            ctx.move(to: p0)
            ctx.addLine(to: base)
            ctx.strokePath()
            ctx.setFillColor(a.color.cgColor())
            ctx.move(to: p1)
            ctx.addLine(to: CGPoint(x: p1.x - cos(angle - spread) * headLen, y: p1.y - sin(angle - spread) * headLen))
            ctx.addLine(to: CGPoint(x: p1.x - cos(angle + spread) * headLen, y: p1.y - sin(angle + spread) * headLen))
            ctx.closePath()
            ctx.fillPath()

        case .rectangle:
            let r = scaled(a.rect)
            ctx.setStrokeColor(a.color.cgColor())
            ctx.setLineWidth(3.5 * u)
            ctx.setLineJoin(.round)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(3 * u, r.width / 2), cornerHeight: min(3 * u, r.height / 2), transform: nil))
            ctx.strokePath()

        case .square:
            var r = scaled(a.rect)
            let side = min(r.width, r.height)
            r = CGRect(x: r.minX, y: r.minY, width: side, height: side)
            ctx.setStrokeColor(a.color.cgColor())
            ctx.setLineWidth(3.5 * u)
            ctx.setLineJoin(.round)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(3 * u, r.width / 2), cornerHeight: min(3 * u, r.height / 2), transform: nil))
            ctx.strokePath()

        case .circle:
            let r = scaled(a.rect)
            ctx.setStrokeColor(a.color.cgColor())
            ctx.setLineWidth(3.5 * u)
            ctx.strokeEllipse(in: r)

        case .triangle:
            let r = scaled(a.rect)
            ctx.setStrokeColor(a.color.cgColor())
            ctx.setLineWidth(3.5 * u)
            ctx.setLineJoin(.round)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: r.midX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.strokePath()

        case .redact:
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(scaled(a.rect))

        case .pixelate:
            ctx.clip(to: scaled(a.rect))
            if let pixelated {
                drawImage(pixelated, in: CGRect(origin: .zero, size: size), ctx, interpolation: .none)
            } else {
                ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
                ctx.fill(scaled(a.rect))
            }

        case .badge:
            guard let p = a.points.first else { return }
            let c = pt(p), r = 13 * u
            let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(a.color.cgColor())
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
            ctx.setLineWidth(2 * u)
            ctx.strokeEllipse(in: circle)
            let label = "\(a.number ?? 1)"
            let font = NSFont.systemFont(ofSize: 15 * u, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: a.color.onColor]
            let s = (label as NSString).size(withAttributes: attrs)
            drawText(label, at: CGPoint(x: c.x - s.width / 2, y: c.y - s.height / 2), attributes: attrs, in: ctx)

        case .text:
            guard let p = a.points.first, let text = a.text, !text.isEmpty else { return }
            let o = pt(p)
            let font = NSFont.systemFont(ofSize: max(11, 15 * u), weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: a.color.onColor]
            let s = (text as NSString).size(withAttributes: attrs)
            let padX = 7 * u, padY = 4 * u
            let box = CGRect(x: o.x, y: o.y, width: s.width + padX * 2, height: s.height + padY * 2)
            ctx.setFillColor(a.color.cgColor())
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: 5 * u, cornerHeight: 5 * u, transform: nil))
            ctx.fillPath()
            drawText(text, at: CGPoint(x: o.x + padX, y: o.y + padY), attributes: attrs, in: ctx)
        }
    }

    /// Draws text upright in a y-down context.
    static func drawText(_ string: String, at origin: CGPoint, attributes: [NSAttributedString.Key: Any], in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (string as NSString).draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}
