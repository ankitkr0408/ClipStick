import AppKit

/// Eyedropper + colour formatting + dominant-palette extraction.
enum ColorService {
    static func hex(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        return String(format: "#%02X%02X%02X", Int((s.redComponent * 255).rounded()), Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
    }

    static func rgb(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        return "rgb(\(Int((s.redComponent * 255).rounded())), \(Int((s.greenComponent * 255).rounded())), \(Int((s.blueComponent * 255).rounded())))"
    }

    static func hsl(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        let (r, g, b) = (s.redComponent, s.greenComponent, s.blueComponent)
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        var h: CGFloat = 0, sat: CGFloat = 0
        if d > 0 {
            sat = d / (1 - abs(2 * l - 1))
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h *= 60; if h < 0 { h += 360 }
        }
        return "hsl(\(Int(h.rounded())), \(Int((sat * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }

    /// Shows the system magnifier; copies the HEX of the picked pixel. Calls `done` with the colour (nil if cancelled).
    @MainActor static func pickFromScreen(done: @escaping (NSColor?) -> Void) {
        NSColorSampler().show { done($0) }
    }

    /// Up to `count` dominant colours via coarse 4-bit-per-channel bucketing, most frequent first.
    static func palette(from image: CGImage, count: Int = 5) -> [NSColor] {
        let side = 64
        var data = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &data, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var buckets: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 128 {
            let (r, g, b) = (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let e = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (e.n + 1, e.r + r, e.g + g, e.b + b)
        }
        var out: [NSColor] = []
        for e in buckets.values.sorted(by: { $0.n > $1.n }) {
            let c = NSColor(srgbRed: CGFloat(e.r / e.n) / 255, green: CGFloat(e.g / e.n) / 255, blue: CGFloat(e.b / e.n) / 255, alpha: 1)
            // Skip near-duplicates of colours already chosen.
            if out.contains(where: { distance($0, c) < 0.12 }) { continue }
            out.append(c)
            if out.count == count { break }
        }
        return out
    }

    private static func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let (x, y) = (a.usingColorSpace(.sRGB)!, b.usingColorSpace(.sRGB)!)
        let (dr, dg, db) = (x.redComponent - y.redComponent, x.greenComponent - y.greenComponent, x.blueComponent - y.blueComponent)
        return sqrt(dr * dr + dg * dg + db * db)
    }
}
