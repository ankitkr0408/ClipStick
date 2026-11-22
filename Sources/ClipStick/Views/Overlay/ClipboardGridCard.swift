import AppKit
import SwiftUI

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let loaded = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        if let loaded { cache.setObject(loaded, forKey: url as NSURL) }
        return loaded
    }
}

@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]
    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image { Image(nsImage: image).resizable().scaledToFill() }
                else { ProgressView().controlSize(.small) }
            }
            .clipped()
            .task(id: url) { image = await ThumbnailCache.shared.image(for: url) }
    }
}

struct ClipboardGridCard: View {
    let item: ClipItem
    let vm: ClipboardViewModel
    let isSelected: Bool
    let isFocused: Bool
    let order: Int?
    let selectionActive: Bool

    @State private var hovering = false
    private let previewHeight: CGFloat = 124

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(height: previewHeight)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) { checkbox.padding(6) }
                .overlay(alignment: .topTrailing) { if hovering { quickActions.padding(6) } }
            caption
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.75)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : (isFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08)),
                              lineWidth: isSelected ? 2.5 : (isFocused ? 2 : 1)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
        .onTapGesture { vm.activate(item) }
        .onDrag { vm.dragProvider(for: item) }
        .opacity(item.isTrashed ? 0.7 : 1)
    }

    // MARK: Preview area

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .image:
            if let name = item.thumbName ?? item.displayBlobName {
                ThumbnailView(url: vm.storage.thumbURL(name))
            } else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary) }
        case .file, .video:
            VStack(spacing: 6) {
                Image(systemName: item.kind == .video ? "film" : "doc.fill").font(.system(size: 30)).foregroundStyle(.secondary)
                Text(item.preview).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 10)
            }
        default:
            Text(String((item.text ?? item.preview).prefix(600)))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(item.kind == .url ? Color.accentColor : Color.primary)
                .lineLimit(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.top, 32)   // clear of the selection checkbox
        }
    }

    private var checkbox: some View {
        let visible = hovering || selectionActive || isSelected
        return ZStack {
            Circle().fill(isSelected ? Color.accentColor : Color.black.opacity(0.35))
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
            if let order, isSelected {
                Text("\(order)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
        .opacity(visible ? 1 : 0)
        .contentShape(Circle())
        .onTapGesture { vm.toggleSelect(item) }
        .help("Select (click order = stitch order)")
    }

    private var quickActions: some View {
        HStack(spacing: 4) {
            if item.isTrashed {
                action("arrow.uturn.backward", "Restore") { vm.restore(item) }
                action("trash.slash", "Delete forever") { vm.delete(item) }
            } else {
                action("doc.on.doc", "Copy") { vm.copyAndDismiss(item) }
                action("pin", "Pin on top of screen") { vm.pin(item) }
                if vm.canFormat(item) { action("curlybraces", "Format & copy (JSON / SQL)") { vm.formatAndCopy(item) } }
                if item.kind == .image {
                    action("pencil.and.outline", "Annotate / crop (⌘E)") { vm.beginEdit(item) }
                    action("paintpalette", "Copy colour palette (HEX)") { vm.copyPalette(item) }
                    if let ocr = item.ocrText, !ocr.isEmpty {
                        action("text.viewfinder", "Copy text from image (OCR)") { vm.copyOCR(item) }
                    }
                }
                action(item.isFavorite ? "star.fill" : "star", "Favorite") { vm.toggleFavorite(item) }
                action("trash", "Delete") { vm.delete(item) }
            }
        }
    }

    private func action(_ symbol: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.ultraThickMaterial))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Caption

    private var caption: some View {
        HStack(spacing: 6) {
            if let icon = AppIconCache.icon(for: item.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            } else {
                Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 14)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.sourceApp ?? kindTitle).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.kind == .image, let ocr = item.ocrText, !ocr.isEmpty {
                Image(systemName: "text.viewfinder").font(.system(size: 10)).foregroundStyle(.secondary).help("Text recognised")
            }
            if item.renderedBlobName != nil {
                Image(systemName: "pencil.tip.crop.circle").font(.system(size: 10)).foregroundStyle(Color.accentColor).help("Annotated")
            }
            if item.isFavorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private var symbol: String {
        switch item.kind {
        case .image: "photo"
        case .url: "link"
        case .file: "doc"
        case .video: "film"
        default: "text.alignleft"
        }
    }

    private var kindTitle: String { item.kind == .url ? "Link" : item.kind.rawValue.capitalized }

    private var subtitle: String {
        let when = -item.createdAt.timeIntervalSinceNow < 10
            ? "just now"
            : item.createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        if item.kind == .image, item.pixelWidth > 0 { return "\(item.pixelWidth)×\(item.pixelHeight) · \(when)" }
        return when
    }
}
