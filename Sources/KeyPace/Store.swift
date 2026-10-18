import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite database in ~/Library/Application Support/KeyPace/keypace.sqlite
final class Store {
    private var db: OpaquePointer?
    let url: URL

    init() {
        url = AppPaths.dataDir.appendingPathComponent("keypace.sqlite")
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            NSLog("KeyPace: cannot open database at \(url.path)")
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("""
        CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start REAL NOT NULL,
            end REAL NOT NULL,
            app_bundle TEXT NOT NULL,
            app_name TEXT NOT NULL,
            chars INTEGER NOT NULL,
            backspaces INTEGER NOT NULL,
            active_seconds REAL NOT NULL,
            peak_wpm REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS sessions_start ON sessions(start);
        """)
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err {
            NSLog("KeyPace SQL error: \(String(cString: err))")
            sqlite3_free(err)
        }
    }

    @discardableResult
    func insert(_ s: TypingSession) -> Int64 {
        let sql = """
        INSERT INTO sessions (start, end, app_bundle, app_name, chars, backspaces, active_seconds, peak_wpm)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, s.start.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, s.end.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, s.appBundleID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, s.appName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 5, Int64(s.chars))
        sqlite3_bind_int64(stmt, 6, Int64(s.backspaces))
        sqlite3_bind_double(stmt, 7, s.activeSeconds)
        sqlite3_bind_double(stmt, 8, s.peakWPM)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
        return sqlite3_last_insert_rowid(db)
    }

    func all() -> [TypingSession] {
        var stmt: OpaquePointer?
        let sql = "SELECT id, start, end, app_bundle, app_name, chars, backspaces, active_seconds, peak_wpm FROM sessions ORDER BY start;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [TypingSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(TypingSession(
                id: sqlite3_column_int64(stmt, 0),
                start: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                end: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                appBundleID: String(cString: sqlite3_column_text(stmt, 3)),
                appName: String(cString: sqlite3_column_text(stmt, 4)),
                chars: Int(sqlite3_column_int64(stmt, 5)),
                backspaces: Int(sqlite3_column_int64(stmt, 6)),
                activeSeconds: sqlite3_column_double(stmt, 7),
                peakWPM: sqlite3_column_double(stmt, 8)
            ))
        }
        return out
    }

    func delete(ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        exec("DELETE FROM sessions WHERE id IN (\(ids.map(String.init).joined(separator: ",")));")
    }

    func deleteAll() { exec("DELETE FROM sessions;") }
}
