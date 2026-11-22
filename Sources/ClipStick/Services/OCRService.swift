import CoreGraphics
import Foundation
import Vision

/// Apple Vision text recognition tuned for code / logs (no language correction, indentation reconstructed).
enum OCRService {
    static func recognize(_ image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = ProcessInfo.processInfo.isLowPowerModeEnabled ? .fast : .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let observations = request.results, !observations.isEmpty else { return nil }

        struct Piece { let text: String; let minX: Double; let width: Double; let midY: Double; let height: Double }
        let imageW = Double(image.width)
        let pieces: [Piece] = observations.compactMap { o in
            guard let text = o.topCandidates(1).first?.string, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let b = o.boundingBox
            return Piece(text: text, minX: b.minX, width: b.width, midY: b.midY, height: b.height)
        }
        guard !pieces.isEmpty else { return nil }

        // Approximate monospace character width (in pixels) from the recognised lines.
        let widths = pieces.filter { $0.text.count >= 4 }.map { $0.width * imageW / Double($0.text.count) }.sorted()
        let charW = max(1, widths.isEmpty ? 8 : widths[widths.count / 2])
        let leftMargin = pieces.map(\.minX).min() ?? 0

        // Group pieces that sit on the same visual row, top to bottom.
        var rows: [[Piece]] = []
        for p in pieces.sorted(by: { $0.midY > $1.midY }) {
            if let last = rows.last?.first, abs(last.midY - p.midY) < max(last.height, p.height) * 0.5 {
                rows[rows.count - 1].append(p)
            } else {
                rows.append([p])
            }
        }
        let lines: [String] = rows.map { row in
            let sorted = row.sorted { $0.minX < $1.minX }
            let indent = min(40, max(0, Int(((sorted[0].minX - leftMargin) * imageW / charW).rounded())))
            var line = String(repeating: " ", count: indent) + sorted[0].text
            for (prev, next) in zip(sorted, sorted.dropFirst()) {
                let gap = (next.minX - (prev.minX + prev.width)) * imageW / charW
                line += String(repeating: " ", count: max(1, Int(gap.rounded()))) + next.text
            }
            return line
        }
        return lines.joined(separator: "\n")
    }
}
