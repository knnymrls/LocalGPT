import Foundation
import GRDB

/// A single serialized writer gives durable changes a deterministic order.
/// SQL handles revisions/tombstones so an older asynchronous save cannot resurrect data.
actor WorkspaceDatabase {
    enum Collection: String, Sendable { case conversations, attachments, memories }
    private let queue: DatabaseQueue
    private var cachedCollections: [Collection: any Sendable] = [:]

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var root = url.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        queue = try DatabaseQueue(path: url.path)
        var migrations = DatabaseMigrator()
        migrations.registerMigration("workspace-v1") { db in
            try db.execute(sql: """
                CREATE TABLE records (
                    collection TEXT NOT NULL, id TEXT NOT NULL, payload BLOB NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 0, updated REAL NOT NULL,
                    PRIMARY KEY (collection, id)
                );
                CREATE TABLE tombstones (collection TEXT NOT NULL, id TEXT NOT NULL,
                    PRIMARY KEY (collection, id));
                CREATE VIRTUAL TABLE passages USING fts5(sourceID UNINDEXED, locator UNINDEXED, content);
                CREATE TABLE extraction_cache (fingerprint TEXT PRIMARY KEY, payload BLOB NOT NULL);
                """)
        }
        try migrations.migrate(queue)
    }

    func hasRecordOrTombstone(_ id: UUID, in collection: Collection) throws -> Bool {
        try queue.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM records WHERE collection=? AND id=?)
                    OR EXISTS(SELECT 1 FROM tombstones WHERE collection=? AND id=?)
                """, arguments: [collection.rawValue, id.uuidString, collection.rawValue, id.uuidString]) ?? false
        }
    }

    func readAll<T: Decodable & Sendable>(_ collection: Collection, as: T.Type) throws -> [T] {
        if let cached = cachedCollections[collection] as? [T] { return cached }
        let items = try queue.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM records WHERE collection = ? ORDER BY updated DESC",
                              arguments: [collection.rawValue]).map { try JSONDecoder().decode(T.self, from: $0) }
        }
        cachedCollections[collection] = items
        return items
    }

    @discardableResult
    func save<T: Encodable & Sendable>(_ item: T, id: UUID, in collection: Collection, revision: Int = 0) throws -> Bool {
        let data = try JSONEncoder().encode(item)
        cachedCollections[collection] = nil
        return try queue.write { db in
            guard try !Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM tombstones WHERE collection=? AND id=?)",
                                     arguments: [collection.rawValue, id.uuidString])! else { return false }
            try db.execute(sql: """
                INSERT INTO records(collection,id,payload,revision,updated) VALUES (?,?,?,?,?)
                ON CONFLICT(collection,id) DO UPDATE SET payload=excluded.payload,
                revision=excluded.revision,updated=excluded.updated WHERE excluded.revision >= records.revision
                """, arguments: [collection.rawValue, id.uuidString, data, revision, Date.now.timeIntervalSince1970])
            return db.changesCount > 0
        }
    }

    /// Deduplication and insertion share one transaction, including simultaneous voice/text turns.
    func insertMemoryIfNew(_ item: MemoryItem) throws -> Bool {
        try Task.checkCancellation()
        cachedCollections[.memories] = nil
        let data = try JSONEncoder().encode(item)
        return try queue.write { db in
            try Task.checkCancellation()
            if let conversationID = item.conversationID {
                let removed = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM tombstones WHERE collection='conversations' AND id=?)", arguments: [conversationID.uuidString]) ?? false
                guard !removed else { throw CancellationError() }
            }
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM records WHERE collection='memories' AND json_extract(payload, '$.fingerprint')=?)", arguments: [item.fingerprint]) ?? false
            guard !exists else { return false }
            let deleted = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM tombstones WHERE collection='memories' AND id=?)", arguments: [item.id.uuidString]) ?? false
            guard !deleted else { throw CancellationError() }
            try db.execute(sql: "INSERT INTO records(collection,id,payload,revision,updated) VALUES ('memories',?,?,?,?)", arguments: [item.id.uuidString, data, Int(item.updatedAt.timeIntervalSince1970 * 1_000_000), item.updatedAt.timeIntervalSince1970])
            return true
        }
    }

    func delete(_ id: UUID, from collection: Collection) throws {
        cachedCollections[collection] = nil
        try queue.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO tombstones(collection,id) VALUES (?,?)", arguments: [collection.rawValue,id.uuidString])
            try db.execute(sql: "DELETE FROM records WHERE collection=? AND id=?", arguments: [collection.rawValue,id.uuidString])
            if collection == .attachments {
                // Cached extraction is disposable; deletion must remove retained source text too.
                try db.execute(sql: "DELETE FROM extraction_cache")
                try db.execute(sql: "DELETE FROM passages WHERE sourceID=?", arguments: [id.uuidString])
            }
        }
    }

    func cachedExtraction(_ key: String) throws -> [SourcePassage]? {
        try queue.read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM extraction_cache WHERE fingerprint=?", arguments: [key]) else { return nil }
            return try JSONDecoder().decode([SourcePassage].self, from: data)
        }
    }

    func index(_ passages: [SourcePassage], sourceID: UUID, fingerprint: String) throws {
        let data = try JSONEncoder().encode(passages)
        try queue.write { db in
            let deleted = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM tombstones WHERE collection='attachments' AND id=?)", arguments: [sourceID.uuidString]) ?? false
            guard !deleted else { throw CancellationError() }
            try db.execute(sql: "DELETE FROM passages WHERE sourceID=?", arguments: [sourceID.uuidString])
            for p in passages {
                try db.execute(sql: "INSERT INTO passages(sourceID,locator,content) VALUES (?,?,?)", arguments: [sourceID.uuidString,p.locator,p.text])
            }
            try db.execute(sql: "INSERT OR REPLACE INTO extraction_cache(fingerprint,payload) VALUES (?,?)", arguments: [fingerprint,data])
        }
    }

    func search(_ query: String, sourceIDs: Set<UUID>, limit: Int = 6) throws -> [SourcePassage] {
        guard !sourceIDs.isEmpty else { return [] }
        let tokens = query.split { !$0.isLetter && !$0.isNumber }.prefix(12)
        let match = tokens.map { "\"\($0)\"" }.joined(separator: " OR ")
        let placeholders = sourceIDs.map { _ in "?" }.joined(separator: ",")
        return try queue.read { db in
            var sql = "SELECT sourceID,locator,content FROM passages WHERE sourceID IN (\(placeholders))"
            var args = StatementArguments(sourceIDs.map(\.uuidString))
            if !match.isEmpty {
                sql += " AND passages MATCH ? ORDER BY rank"
                args += [match]
            }
            sql += " LIMIT ?"
            args += [min(max(limit,1),12)]
            return try Row.fetchAll(db, sql: sql, arguments: args).compactMap { row in
                guard let id = UUID(uuidString: row["sourceID"]) else { return nil }
                return SourcePassage(sourceID: id, locator: row["locator"], text: row["content"])
            }
        }
    }
}
