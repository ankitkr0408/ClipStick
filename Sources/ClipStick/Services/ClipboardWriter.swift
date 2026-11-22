import AppKit

/// Writes clips (and derived content) back to the system pasteboard, and exports files for drag & drop.
@MainActor
final class ClipboardWriter {
    let storage: StorageService
    private unowned let monitor: PasteboardMonitor

    init(storage: StorageService, monitor: PasteboardMonitor) {
        self.storage = storage
        self.monitor = monitor
    }

    // MARK: Pasteboard

    /// Copies one or more clips. Several text clips are joined into one string; images and files become separate items.
    func write(_ items: [ClipItem]) {
        var writers: [NSPasteboardWriting] = []
        let texts = items.filter { [.text, .richText, .url].contains($0.kind) }.compactMap { $0.text ?? $0.preview }
        if !texts.isEmpty {
            let pbItem = NSPasteboardItem()
            pbItem.setString(texts.joined(separator: "\n\n"), forType: .string)
            writers.append(pbItem)
        }
        for item in items {
            switch item.kind {
            case .image:
                if let w = imageWriter(for: item) { writers.append(w) }
            case .file, .video:
                writers.append(contentsOf: item.fileURLs.map { $0 as NSURL })
            default: break
            }
        }
        commit(writers)
    }

    func writeImage(png: Data) {
        commit([imageWriter(png: png)])
    }

    func writeText(_ text: String) {
        let pbItem = NSPasteboardItem()
        pbItem.setString(text, forType: .string)
        commit([pbItem])
    }

    /// Markdown context for pasting into Claude / ChatGPT / GitHub, plus the screenshots as files.
    /// Returns the markdown that was written.
    @discardableResult
    func writeAIBundle(_ items: [ClipItem]) -> String {
        let dir = makeExportDirectory()
        var shot = 0
        var fileWriters: [NSPasteboardWriting] = []
        var md = "### Bug Analysis Context\n\n"

        for (index, item) in items.enumerated() {
            let n = index + 1
            let from = item.sourceApp.map { ", from \($0)" } ?? ""
            switch item.kind {
            case .image:
                shot += 1
                let name = "screenshot-\(shot).png"
                if let src = item.displayBlobName {
                    let dest = dir.appendingPathComponent(name)
                    try? FileManager.default.copyItem(at: storage.blobURL(src), to: dest)
                    fileWriters.append(dest as NSURL)
                }
                let size = item.pixelWidth > 0 ? ", \(item.pixelWidth)×\(item.pixelHeight)" : ""
                md += "- Item \(n): [Attached Screenshot \(shot): `\(name)`\(size)\(from)]\n"
                if let ocr = item.ocrText, !ocr.isEmpty {
                    let excerpt = ocr.count > 1200 ? String(ocr.prefix(1200)) + "\n…" : ocr
                    md += Self.indent("Text detected in screenshot:\n" + Self.fenced(excerpt)) + "\n"
                }
            case .url:
                md += "- Item \(n) (Link\(from)): \(item.text ?? item.preview)\n"
            case .file, .video:
                md += "- Item \(n) (File\(from)): " + item.fileURLs.map { "`\($0.path)`" }.joined(separator: ", ") + "\n"
                fileWriters.append(contentsOf: item.fileURLs.map { $0 as NSURL })
            default:
                let text = (item.text ?? item.preview).trimmingCharacters(in: .newlines)
                if !text.contains("\n"), text.count <= 160, !text.contains("`") {
                    md += "- Item \(n) (Text\(from)): `\(text)`\n"
                } else {
                    md += "- Item \(n) (Text\(from)):\n" + Self.indent(Self.fenced(text)) + "\n"
                }
            }
        }
        let header = NSPasteboardItem()
        header.setString(md, forType: .string)
        commit([header] + fileWriters)
        return md
    }

    // MARK: Export (drag & drop)

    func makeExportDirectory() -> URL {
        let dir = storage.exportsURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Real files for the given clips: annotated PNG copies for images, original paths for files.
    func exportFiles(for items: [ClipItem]) -> [URL] {
        var urls: [URL] = []
        var dir: URL?
        var shot = 0
        for item in items {
            switch item.kind {
            case .image:
                guard let src = item.displayBlobName else { continue }
                shot += 1
                let d = dir ?? makeExportDirectory()
                dir = d
                let dest = d.appendingPathComponent("screenshot-\(shot).png")
                if (try? FileManager.default.copyItem(at: storage.blobURL(src), to: dest)) != nil { urls.append(dest) }
            case .file, .video:
                urls.append(contentsOf: item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) })
            default: break
            }
        }
        return urls
    }

    // MARK: Internals

    private func commit(_ writers: [NSPasteboardWriting]) {
        guard !writers.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(writers)
        monitor.syncChangeCount()
    }

    private func imageWriter(for item: ClipItem) -> NSPasteboardItem? {
        guard let name = item.displayBlobName, let png = try? Data(contentsOf: storage.blobURL(name)) else { return nil }
        return imageWriter(png: png)
    }

    private func imageWriter(png: Data) -> NSPasteboardItem {
        let pbItem = NSPasteboardItem()
        pbItem.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pbItem.setData(tiff, forType: .tiff) }
        return pbItem
    }

    private static func fenced(_ text: String) -> String {
        let fence = text.contains("```") ? "````" : "```"
        return "\(fence)\n\(text)\n\(fence)"
    }

    private static func indent(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
    }
}
