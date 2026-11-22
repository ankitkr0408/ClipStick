import AppKit
import CoreGraphics

func createIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    ctx.interpolationQuality = .high

    // 1. Squircle background (standard macOS icon shape)
    let inset = s * 0.08
    let iconRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = iconRect.width * 0.224

    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Shadow under squircle
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.03), blur: s * 0.04, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Squircle background gradient (Dark navy to vibrant violet/blue)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let gradColors = [
        CGColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0), // Deep slate #0F172A
        CGColor(srgbRed: 0.11, green: 0.18, blue: 0.35, alpha: 1.0), // Royal indigo
        CGColor(srgbRed: 0.13, green: 0.35, blue: 0.75, alpha: 1.0)  // Deep vibrant blue
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 0.5, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: iconRect.midX, y: iconRect.maxY), end: CGPoint(x: iconRect.midX, y: iconRect.minY), options: [])

    // Subtle background mesh glow
    let glowColors = [CGColor(srgbRed: 0.05, green: 0.65, blue: 0.95, alpha: 0.35), CGColor(gray: 0, alpha: 0)] as CFArray
    let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY * 0.8), startRadius: 0,
                                 endCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY * 0.8), endRadius: iconRect.width * 0.6, options: [])

    ctx.restoreGState()

    // Squircle border
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    ctx.setLineWidth(max(1, s * 0.008))
    ctx.strokePath()
    ctx.restoreGState()

    // 2. Clipboard Board Body
    let boardW = iconRect.width * 0.68
    let boardH = iconRect.height * 0.72
    let boardRect = CGRect(x: iconRect.midX - boardW / 2, y: iconRect.midY - boardH / 2 - s * 0.02, width: boardW, height: boardH)
    let boardRadius = boardW * 0.14
    let boardPath = CGPath(roundedRect: boardRect, cornerWidth: boardRadius, cornerHeight: boardRadius, transform: nil)

    // Board shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(boardPath)
    ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Board interior (White paper with very subtle grey border)
    ctx.saveGState()
    ctx.addPath(boardPath)
    ctx.setStrokeColor(CGColor(gray: 0.8, alpha: 0.6))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokePath()
    ctx.restoreGState()

    // 3. Two overlapping screenshots inside board
    // Screenshot 1 (Top Left card)
    let cardW = boardW * 0.78
    let cardH = boardH * 0.32
    let card1Rect = CGRect(x: boardRect.midX - cardW / 2, y: boardRect.midY + s * 0.03, width: cardW, height: cardH)
    let cardRadius = cardW * 0.08
    let card1Path = CGPath(roundedRect: card1Rect, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)

    ctx.saveGState()
    ctx.addPath(card1Path)
    ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.22, blue: 0.38, alpha: 0.95))
    ctx.fillPath()
    // Simulated code lines on card 1
    ctx.setFillColor(CGColor(srgbRed: 0.38, green: 0.72, blue: 0.98, alpha: 0.8))
    ctx.fill(CGRect(x: card1Rect.minX + cardW * 0.1, y: card1Rect.midY + cardH * 0.12, width: cardW * 0.45, height: cardH * 0.14))
    ctx.setFillColor(CGColor(srgbRed: 0.98, green: 0.65, blue: 0.2, alpha: 0.8))
    ctx.fill(CGRect(x: card1Rect.minX + cardW * 0.1, y: card1Rect.midY - cardH * 0.18, width: cardW * 0.65, height: cardH * 0.14))
    ctx.restoreGState()

    // Screenshot 2 (Bottom card)
    let card2Rect = CGRect(x: boardRect.midX - cardW / 2, y: boardRect.midY - cardH * 1.15, width: cardW, height: cardH)
    let card2Path = CGPath(roundedRect: card2Rect, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)

    ctx.saveGState()
    ctx.addPath(card2Path)
    ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.16, blue: 0.28, alpha: 0.95))
    ctx.fillPath()
    // Simulated lines on card 2
    ctx.setFillColor(CGColor(srgbRed: 0.34, green: 0.85, blue: 0.55, alpha: 0.8))
    ctx.fill(CGRect(x: card2Rect.minX + cardW * 0.1, y: card2Rect.midY + cardH * 0.12, width: cardW * 0.55, height: cardH * 0.14))
    ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.85, blue: 0.92, alpha: 0.7))
    ctx.fill(CGRect(x: card2Rect.minX + cardW * 0.1, y: card2Rect.midY - cardH * 0.18, width: cardW * 0.4, height: cardH * 0.14))
    ctx.restoreGState()

    // 4. Glowing Neon Stitch Line / Seam joining the cards!
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(srgbRed: 0.05, green: 0.78, blue: 0.98, alpha: 1.0)) // Electric Cyan
    ctx.setLineWidth(max(2, s * 0.016))
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [s * 0.025, s * 0.018])
    let seamY = boardRect.midY - s * 0.01
    ctx.move(to: CGPoint(x: boardRect.minX + boardW * 0.12, y: seamY))
    ctx.addLine(to: CGPoint(x: boardRect.maxX - boardW * 0.12, y: seamY))
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Metallic Clip at the top of the board
    let clipW = boardW * 0.42
    let clipH = boardH * 0.18
    let clipRect = CGRect(x: boardRect.midX - clipW / 2, y: boardRect.maxY - clipH * 0.55, width: clipW, height: clipH)
    let clipRadius = clipW * 0.16
    let clipPath = CGPath(roundedRect: clipRect, cornerWidth: clipRadius, cornerHeight: clipRadius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.015, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(clipPath)
    let clipColors = [
        CGColor(srgbRed: 0.75, green: 0.78, blue: 0.82, alpha: 1.0),
        CGColor(srgbRed: 0.55, green: 0.58, blue: 0.65, alpha: 1.0)
    ] as CFArray
    let clipGrad = CGGradient(colorsSpace: colorSpace, colors: clipColors, locations: [0.0, 1.0])!
    ctx.clip()
    ctx.drawLinearGradient(clipGrad, start: CGPoint(x: clipRect.midX, y: clipRect.maxY), end: CGPoint(x: clipRect.midX, y: clipRect.minY), options: [])
    ctx.restoreGState()

    // Clip center metallic pin hole
    let pinW = clipW * 0.35
    let pinH = clipH * 0.32
    let pinRect = CGRect(x: clipRect.midX - pinW / 2, y: clipRect.midY - pinH / 2, width: pinW, height: pinH)
    let pinPath = CGPath(roundedRect: pinRect, cornerWidth: pinH * 0.4, cornerHeight: pinH * 0.4, transform: nil)
    ctx.saveGState()
    ctx.addPath(pinPath)
    ctx.setFillColor(CGColor(srgbRed: 0.25, green: 0.28, blue: 0.35, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func savePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    let img = createIcon(size: px)
    savePNG(img, to: iconsetURL.appendingPathComponent(name))
}

print("Iconset created successfully.")
