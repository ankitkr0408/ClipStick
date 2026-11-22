import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Something captured from the pasteboard or the screenshot folder, before it is stored.
struct CaptureDraft {
    enum Payload {
        case text(String)
        case imageData(Data)
        case imageFile(URL)
        case files([URL])
    }
    var payload: Payload
    var title: String? = nil
    var sourceApp: String? = nil
    var sourceBundleID: String? = nil
}

/// Background pipeline: hash → dedup → blob + thumbnail → SQLite → OCR. Results are published on the main queue.
final class IngestService: @unchecked Sendable {
    private let storage: StorageService
    private let queue = DispatchQueue(label: "clipstick.ingest", qos: .userInitiated)
    /// OCR is the heaviest step and nobody waits on it, so it runs at utility QoS (efficiency cores).
    private let ocrQueue = DispatchQueue(label: "clipstick.ocr", qos: .utility)

    /// Called on the main thread whenever a clip is inserted, bumped or updated. Set once at startup.
    var onUpsert: (@MainActor (ClipItem) -> Void)?
    var onRemoved: (@MainActor ([UUID]) -> Void)?
    var ocrEnabled: @Sendable () -> Bool = { Preferences.ocrEnabled }
    var maxItems: @Sendable () -> Int = { Preferences.maxItems }

    init(storage: StorageService) { self.storage = storage }

    func ingest(_ draft: CaptureDraft) {
        queue.async { self.process(draft) }
    }

    /// Blocks until queued work is done (used by the self-test).
    func drain() { queue.sync {}; ocrQueue.sync {} }

    // MARK: Pipeline

    private func process(_ draft: CaptureDraft) {
        switch draft.payload {
        case .text(let s): processText(s, draft)
        case .imageData(let d): processImage(d, draft)
        case .imageFile(let url):
            guard let d = try? Data(contentsOf: url) else { return }
            processImage(d, draft)
        case .files(let urls): processFiles(urls, draft)
        }
    }

    private func processText(_ raw: String, _ draft: CaptureDraft) {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = String(raw.prefix(1_000_000))
        let hash = Self.sha256("t:" + text)
        if bump(hash: hash) { return }

        let firstLine = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? text
        let isURL: Bool = {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.contains(where: \.isWhitespace), let u = URL(string: t), let scheme = u.scheme?.lowercased() else { return false }
            return (scheme == "http" || scheme == "https") && u.host != nil
        }()
        let item = ClipItem(
            id: UUID(), kind: isURL ? .url : .text, preview: String(firstLine.prefix(200)), text: text,
            byteSize: Int64(text.utf8.count), contentHash: hash, createdAt: Date(),
            sourceApp: draft.sourceApp, sessionID: nil, isFavorite: false, deletedAt: nil,
            sourceBundleID: draft.sourceBundleID
        )
        insert(item)
    }

    private func processFiles(_ urls: [URL], _ draft: CaptureDraft) {
        guard !urls.isEmpty else { return }
        let paths = urls.map(\.path)
        let hash = Self.sha256("f:" + paths.joined(separator: "\n"))
        if bump(hash: hash) { return }

        let allVideos = urls.allSatisfy { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .movie) == true }
        let size = urls.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
        let item = ClipItem(
            id: UUID(), kind: allVideos ? .video : .file,
            preview: urls.map(\.lastPathComponent).joined(separator: ", "),
            text: paths.joined(separator: "\n"), filePath: paths[0],
            byteSize: Int64(size), contentHash: hash, createdAt: Date(),
            sourceApp: draft.sourceApp, sessionID: nil, isFavorite: false, deletedAt: nil,
            sourceBundleID: draft.sourceBundleID
        )
        insert(item)
    }

    private func processImage(_ data: Data, _ draft: CaptureDraft) {
        guard let cg = ImageProcessingService.cgImage(from: data), let hash = ImageProcessingService.pixelHash(cg) else { return }
        if bump(hash: hash) { return }

        let id = UUID()
        guard let png = ImageProcessingService.isPNG(data) ? data : ImageProcessingService.pngData(cg) else { return }
        let blobName = "\(id.uuidString).png"
        do { try png.write(to: storage.blobURL(blobName), options: .atomic) } catch { return }

        var thumbName: String?
        if let thumb = ImageProcessingService.resized(cg, maxPixel: 720), let tp = ImageProcessingService.pngData(thumb) {
            let name = "\(id.uuidString).png"
            if (try? tp.write(to: storage.thumbURL(name), options: .atomic)) != nil { thumbName = name }
        }
        let item = ClipItem(
            id: id, kind: .image, preview: draft.title ?? "Screenshot \(cg.width)×\(cg.height)",
            blobName: blobName, blobExt: "png", thumbName: thumbName,
            byteSize: Int64(png.count), contentHash: hash, createdAt: Date(),
            sourceApp: draft.sourceApp, sessionID: nil, isFavorite: false, deletedAt: nil,
            sourceBundleID: draft.sourceBundleID, pixelWidth: cg.width, pixelHeight: cg.height
        )
        insert(item)

        if ocrEnabled() {
            ocrQueue.async {
                guard let text = OCRService.recognize(cg) else { return }
                self.storage.updateOCR(id: id, text: text)
                if let updated = self.storage.item(id: id) { self.publish(updated) }
            }
        }
    }

    // MARK: Helpers

    /// Same content already stored → move it to the top instead of duplicating.
    private func bump(hash: String) -> Bool {
        guard var existing = storage.find(hash: hash) else { return false }
        existing.createdAt = Date()
        existing.deletedAt = nil
        storage.save(existing)
        publish(existing)
        return true
    }

    private func insert(_ item: ClipItem) {
        storage.save(item)
        publish(item)
        let removed = storage.prune(maxItems: maxItems())
        if !removed.isEmpty {
            let ids = removed.map(\.id)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onRemoved?(ids) } }
        }
    }

    private func publish(_ item: ClipItem) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onUpsert?(item) } }
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
