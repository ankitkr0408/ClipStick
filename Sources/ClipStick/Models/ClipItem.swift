import Foundation

enum ClipKind: String, Codable {
    case text, richText, url, image, video, file
}

/// Sidebar-level categories.
enum ClipCategory: String, CaseIterable, Identifiable {
    case all, text, images, videos, files, favorites, trash
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Items"
        case .text: "Text"
        case .images: "Images"
        case .videos: "Videos"
        case .files: "Files"
        case .favorites: "Favorites"
        case .trash: "Recently Deleted"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .text: "text.alignleft"
        case .images: "photo.on.rectangle"
        case .videos: "film"
        case .files: "doc"
        case .favorites: "star"
        case .trash: "trash"
        }
    }

    /// Kinds included in this category (nil = no kind filter).
    var kinds: [ClipKind]? {
        switch self {
        case .text: [.text, .richText, .url]
        case .images: [.image]
        case .videos: [.video]
        case .files: [.file]
        default: nil
        }
    }
}

struct ClipItem: Identifiable, Hashable {
    var id: UUID
    var kind: ClipKind
    var preview: String          // short display string (text snippet / file name)
    var text: String?            // plain text payload, if any
    var blobName: String?        // file in blob store (image data, RTF data, ...)
    var blobExt: String?
    var thumbName: String?       // thumbnail file in thumbs store
    var filePath: String?        // original file reference for file/video items
    var byteSize: Int64
    var contentHash: String
    var createdAt: Date
    var sourceApp: String?
    var sessionID: UUID?
    var isFavorite: Bool
    var deletedAt: Date?

    // MARK: Screenshot / debugging extensions
    var sourceBundleID: String? = nil
    var ocrText: String? = nil            // Apple Vision text recognised in an image clip
    var editStateJSON: String? = nil      // JSON-encoded `EditState` (annotations + crop)
    var renderedBlobName: String? = nil   // flattened export of original + edits (original is never modified)
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
}

extension ClipItem {
    /// The blob that should be pasted / dragged: the annotated render when one exists.
    var displayBlobName: String? { renderedBlobName ?? blobName }

    var isTrashed: Bool { deletedAt != nil }

    /// File URLs for `.file` / `.video` clips (stored newline-separated in `text`).
    var fileURLs: [URL] {
        guard kind == .file || kind == .video, let text else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    var editState: EditState? {
        guard let editStateJSON, let data = editStateJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(EditState.self, from: data)
    }

    /// Lower-cased text used by the search box (bounded so huge clips stay cheap to scan).
    var searchHaystack: String {
        [preview, String((text ?? "").prefix(20_000)), String((ocrText ?? "").prefix(20_000)), sourceApp ?? ""]
            .joined(separator: "\n").lowercased()
    }
}
