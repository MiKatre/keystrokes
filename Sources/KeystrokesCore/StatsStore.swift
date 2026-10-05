import Foundation
import CSQLite

// Accessed on the main actor by the app; tests use independent database instances.
public final class StatsStore {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keystrokes/stats.sqlite")
    }
    public let url: URL
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            let error = failure()
            sqlite3_close(database)
            database = nil
            throw error
        }
        sqlite3_busy_timeout(database, 3000)
        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("""
                CREATE TABLE IF NOT EXISTS daily (
                    day TEXT NOT NULL, source TEXT NOT NULL, bundle_id TEXT NOT NULL DEFAULT '',
                    app_name TEXT NOT NULL DEFAULT '', keys INTEGER NOT NULL DEFAULT 0 CHECK(keys >= 0),
                    clicks INTEGER NOT NULL DEFAULT 0 CHECK(clicks >= 0), legacy_json TEXT,
                    PRIMARY KEY(day, source, bundle_id)
                )
                """)
            try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            try execute("PRAGMA user_version=1")
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    public func record(day: String, bundleID: String, appName: String, keys: Int64, clicks: Int64) throws {
        guard keys >= 0, clicks >= 0 else { throw DataError.message("Counters cannot be negative.") }
        try statement("""
            INSERT INTO daily(day, source, bundle_id, app_name, keys, clicks) VALUES (?, 'native', ?, ?, ?, ?)
            ON CONFLICT(day, source, bundle_id) DO UPDATE SET
                keys=daily.keys+excluded.keys, clicks=daily.clicks+excluded.clicks, app_name=excluded.app_name
            """) { stmt in
            bind(day, at: 1, to: stmt); bind(bundleID, at: 2, to: stmt); bind(appName, at: 3, to: stmt)
            sqlite3_bind_int64(stmt, 4, keys); sqlite3_bind_int64(stmt, 5, clicks)
            try stepDone(stmt)
        }
    }

    // Freeze imported snapshots. Never import a date already collected natively:
    // OctoMouse may still be running, and its later totals overlap ours.
    public func importHistory(_ days: [LegacyDay]) throws -> ImportResult {
        var imported = 0
        try execute("BEGIN IMMEDIATE")
        do {
            for day in days {
                let payload = String(decoding: try JSONEncoder().encode(day), as: UTF8.self)
                try statement("""
                    INSERT INTO daily(day, source, keys, clicks, legacy_json)
                    SELECT ?, 'octomouse', ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM daily WHERE day=?)
                    """) { stmt in
                    bind(day.day, at: 1, to: stmt); sqlite3_bind_int64(stmt, 2, day.keyDown)
                    sqlite3_bind_int64(stmt, 3, day.clicks); bind(payload, at: 4, to: stmt)
                    bind(day.day, at: 5, to: stmt); try stepDone(stmt)
                    imported += Int(sqlite3_changes(database))
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        return ImportResult(imported: imported, skipped: days.count - imported)
    }

    public func days() throws -> [DayStats] {
        var result: [DayStats] = []
        try statement("SELECT day, SUM(keys), SUM(clicks) FROM daily GROUP BY day ORDER BY day") { stmt in
            while try next(stmt) {
                result.append(DayStats(day: string(stmt, 0), keys: sqlite3_column_int64(stmt, 1), clicks: sqlite3_column_int64(stmt, 2)))
            }
        }
        return result
    }

    public func apps(day: String) throws -> [AppStats] {
        var result: [AppStats] = []
        try statement("SELECT bundle_id, app_name, SUM(keys), SUM(clicks) FROM daily WHERE source='native' AND day=? GROUP BY bundle_id ORDER BY SUM(keys)+SUM(clicks) DESC LIMIT 5") { stmt in
            bind(day, at: 1, to: stmt)
            while try next(stmt) {
                result.append(AppStats(bundleID: string(stmt, 0), name: string(stmt, 1), keys: sqlite3_column_int64(stmt, 2), clicks: sqlite3_column_int64(stmt, 3)))
            }
        }
        return result
    }

    public func importedDays() throws -> Int {
        var count = 0
        try statement("SELECT COUNT(*) FROM daily WHERE source='octomouse'") { stmt in
            if try next(stmt) { count = Int(sqlite3_column_int64(stmt, 0)) }
        }
        return count
    }

    public func metadata(_ key: String) throws -> String? {
        var value: String?
        try statement("SELECT value FROM metadata WHERE key=?") { stmt in
            bind(key, at: 1, to: stmt)
            if try next(stmt) { value = string(stmt, 0) }
        }
        return value
    }

    public func setMetadata(_ key: String, value: String) throws {
        try statement("INSERT INTO metadata(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value") { stmt in
            bind(key, at: 1, to: stmt); bind(value, at: 2, to: stmt); try stepDone(stmt)
        }
    }

    public func exportCSV(to url: URL) throws {
        let rows = try days().map { "\($0.day),\($0.keys),\($0.clicks)" }
        try ("date,keystrokes,mouse_clicks\n" + rows.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    private func statement(_ sql: String, body: (OpaquePointer) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        try body(stmt)
    }

    private func bind(_ value: String, at index: Int32, to stmt: OpaquePointer) {
        _ = value.withCString { sqlite3_bind_text(stmt, index, $0, -1, transient) }
    }

    private func next(_ stmt: OpaquePointer) throws -> Bool {
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw failure()
        }
    }

    private func stepDone(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }

    private func string(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: value)
    }

    private func failure() -> DataError {
        .message(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open the statistics database.")
    }
}
