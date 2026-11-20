import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum StorageError: Error, LocalizedError {
    case open(String)
    case sql(String)
    var errorDescription: String? {
        switch self {
        case .open(let m): "Could not open the ClipCoard database: \(m)"
        case .sql(let m): "Database error: \(m)"
        }
    }
}

/// SQLite metadata store + on-disk blob manager.
/// Layout: `~/Library/Application Support/ClipCoard/{clipcoard.sqlite, blobs/, thumbs/, exports/}`.
final class StorageService: @unchecked Sendable {
    let rootURL: URL
    let blobsURL: URL
    let thumbsURL: URL
    let exportsURL: URL

    private var db: OpaquePointer?
    private let lock = NSLock()

    private static let columns = """
        id, kind, preview, text, blob_name, blob_ext, thumb_name, file_path, byte_size, content_hash, \
        created_at, source_app, source_bundle_id, session_id, is_favorite, deleted_at, ocr_text, \
        edit_state_json, rendered_blob_name, pixel_width, pixel_height
        """

    init(rootURL: URL? = nil) throws {
        let root = rootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipCoard", isDirectory: true)
        self.rootURL = root
        blobsURL = root.appendingPathComponent("blobs", isDirectory: true)
        thumbsURL = root.appendingPathComponent("thumbs", isDirectory: true)
        exportsURL = root.appendingPathComponent("exports", isDirectory: true)
        for dir in [root, blobsURL, thumbsURL, exportsURL] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let path = root.appendingPathComponent("clipcoard.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw StorageError.open(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_busy_timeout(db, 3000)
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY, kind TEXT NOT NULL, preview TEXT NOT NULL DEFAULT '',
                text TEXT, blob_name TEXT, blob_ext TEXT, thumb_name TEXT, file_path TEXT,
                byte_size INTEGER NOT NULL DEFAULT 0, content_hash TEXT NOT NULL,
                created_at REAL NOT NULL, source_app TEXT, source_bundle_id TEXT, session_id TEXT,
                is_favorite INTEGER NOT NULL DEFAULT 0, deleted_at REAL, ocr_text TEXT,
                edit_state_json TEXT, rendered_blob_name TEXT,
                pixel_width INTEGER NOT NULL DEFAULT 0, pixel_height INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_clips_hash ON clips(content_hash);
            CREATE INDEX IF NOT EXISTS idx_clips_created ON clips(created_at DESC);
            """)
    }

    deinit { sqlite3_close(db) }

    // MARK: Blob paths

    func blobURL(_ name: String) -> URL { blobsURL.appendingPathComponent(name) }
    func thumbURL(_ name: String) -> URL { thumbsURL.appendingPathComponent(name) }

    func removeFiles(for item: ClipItem) {
        let fm = FileManager.default
        if let n = item.blobName { try? fm.removeItem(at: blobURL(n)) }
        if let n = item.renderedBlobName { try? fm.removeItem(at: blobURL(n)) }
        if let n = item.thumbName { try? fm.removeItem(at: thumbURL(n)) }
        try? fm.removeItem(at: thumbURL("\(item.id.uuidString).png"))   // pristine thumbnail kept across edits
    }

    // MARK: CRUD

    func fetchAll(limit: Int = 5000) -> [ClipItem] {
        query("SELECT \(Self.columns) FROM clips ORDER BY created_at DESC LIMIT ?") {
            sqlite3_bind_int(self.stmt($0), 1, Int32(limit))
        }
    }

    func item(id: UUID) -> ClipItem? {
        query("SELECT \(Self.columns) FROM clips WHERE id = ?") { Self.bind($0, 1, id.uuidString) }.first
    }

    func find(hash: String) -> ClipItem? {
        query("SELECT \(Self.columns) FROM clips WHERE content_hash = ? LIMIT 1") { Self.bind($0, 1, hash) }.first
    }

    @discardableResult
    func save(_ item: ClipItem) -> Bool {
        run("""
            INSERT OR REPLACE INTO clips (\(Self.columns)) \
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """) { s in
            Self.bind(s, 1, item.id.uuidString)
            Self.bind(s, 2, item.kind.rawValue)
            Self.bind(s, 3, item.preview)
            Self.bind(s, 4, item.text)
            Self.bind(s, 5, item.blobName)
            Self.bind(s, 6, item.blobExt)
            Self.bind(s, 7, item.thumbName)
            Self.bind(s, 8, item.filePath)
            sqlite3_bind_int64(s, 9, item.byteSize)
            Self.bind(s, 10, item.contentHash)
            sqlite3_bind_double(s, 11, item.createdAt.timeIntervalSince1970)
            Self.bind(s, 12, item.sourceApp)
            Self.bind(s, 13, item.sourceBundleID)
            Self.bind(s, 14, item.sessionID?.uuidString)
            sqlite3_bind_int(s, 15, item.isFavorite ? 1 : 0)
            if let d = item.deletedAt { sqlite3_bind_double(s, 16, d.timeIntervalSince1970) } else { sqlite3_bind_null(s, 16) }
            Self.bind(s, 17, item.ocrText)
            Self.bind(s, 18, item.editStateJSON)
            Self.bind(s, 19, item.renderedBlobName)
            sqlite3_bind_int(s, 20, Int32(item.pixelWidth))
            sqlite3_bind_int(s, 21, Int32(item.pixelHeight))
        }
    }

    func updateOCR(id: UUID, text: String) {
        run("UPDATE clips SET ocr_text = ? WHERE id = ?") {
            Self.bind($0, 1, text)
            Self.bind($0, 2, id.uuidString)
        }
    }

    func delete(id: UUID) {
        run("DELETE FROM clips WHERE id = ?") { Self.bind($0, 1, id.uuidString) }
    }

    /// Removes trashed clips past retention and non-favourites beyond `maxItems`. Returns what was removed
    /// (files are already deleted).
    @discardableResult
    func prune(maxItems: Int, trashRetentionDays: Int = 30) -> [ClipItem] {
        let cutoff = Date().addingTimeInterval(-Double(trashRetentionDays) * 86_400).timeIntervalSince1970
        var doomed = query("""
            SELECT \(Self.columns) FROM clips WHERE deleted_at IS NOT NULL AND deleted_at < ? AND is_favorite = 0
            """) { sqlite3_bind_double($0, 1, cutoff) }
        doomed += query("""
            SELECT \(Self.columns) FROM clips WHERE is_favorite = 0 AND deleted_at IS NULL \
            ORDER BY created_at DESC LIMIT -1 OFFSET ?
            """) { sqlite3_bind_int($0, 1, Int32(maxItems)) }
        for item in doomed {
            delete(id: item.id)
            removeFiles(for: item)
        }
        return doomed
    }

    // MARK: SQLite plumbing

    private func stmt(_ s: OpaquePointer) -> OpaquePointer { s }

    private func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw StorageError.sql(msg)
        }
    }

    @discardableResult
    private func run(_ sql: String, _ bind: (OpaquePointer) -> Void = { _ in }) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else {
            NSLog("ClipCoard SQL prepare failed: %@", String(cString: sqlite3_errmsg(db)))
            return false
        }
        defer { sqlite3_finalize(s) }
        bind(s)
        let rc = sqlite3_step(s)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            NSLog("ClipCoard SQL step failed: %@", String(cString: sqlite3_errmsg(db)))
            return false
        }
        return true
    }

    private func query(_ sql: String, _ bind: (OpaquePointer) -> Void = { _ in }) -> [ClipItem] {
        lock.lock(); defer { lock.unlock() }
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else {
            NSLog("ClipCoard SQL prepare failed: %@", String(cString: sqlite3_errmsg(db)))
            return []
        }
        defer { sqlite3_finalize(s) }
        bind(s)
        var rows: [ClipItem] = []
        while sqlite3_step(s) == SQLITE_ROW { rows.append(Self.item(from: s)) }
        return rows
    }

    private static func bind(_ s: OpaquePointer, _ i: Int32, _ v: String?) {
        if let v { sqlite3_bind_text(s, i, v, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(s, i) }
    }

    private static func item(from s: OpaquePointer) -> ClipItem {
        func str(_ i: Int32) -> String? { sqlite3_column_text(s, i).map { String(cString: $0) } }
        let deleted: Date? = sqlite3_column_type(s, 15) == SQLITE_NULL
            ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 15))
        return ClipItem(
            id: UUID(uuidString: str(0) ?? "") ?? UUID(),
            kind: ClipKind(rawValue: str(1) ?? "") ?? .text,
            preview: str(2) ?? "",
            text: str(3),
            blobName: str(4),
            blobExt: str(5),
            thumbName: str(6),
            filePath: str(7),
            byteSize: sqlite3_column_int64(s, 8),
            contentHash: str(9) ?? "",
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 10)),
            sourceApp: str(11),
            sessionID: str(13).flatMap { UUID(uuidString: $0) },
            isFavorite: sqlite3_column_int(s, 14) != 0,
            deletedAt: deleted,
            sourceBundleID: str(12),
            ocrText: str(16),
            editStateJSON: str(17),
            renderedBlobName: str(18),
            pixelWidth: Int(sqlite3_column_int(s, 19)),
            pixelHeight: Int(sqlite3_column_int(s, 20))
        )
    }
}
