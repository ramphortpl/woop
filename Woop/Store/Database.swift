import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// On-device store (SQLite, WAL). Every call runs on one serial queue, so it is safe from the
/// BLE queue, the analytics queue and the main thread alike. Nothing ever leaves the phone.
final class Database {
    static let shared = Database()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "woop.db")
    private(set) var path: String = ""

    private init() {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let url = dir.appendingPathComponent("woop.sqlite")
        path = url.path
        queue.sync {
            if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
                db = nil
                return
            }
            exec("PRAGMA journal_mode=WAL;")
            exec("PRAGMA synchronous=NORMAL;")
            migrate()
        }
        var url2 = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try? url2.setResourceValues(values)
    }

    // MARK: - Schema

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS sample (
          ts INTEGER PRIMARY KEY,
          hr INTEGER NOT NULL,
          rrn INTEGER NOT NULL DEFAULT 0,
          rr0 INTEGER, rr1 INTEGER, rr2 INTEGER, rr3 INTEGER,
          gx REAL, gy REAL, gz REAL, dyn REAL,
          steps INTEGER, cadence INTEGER, act INTEGER,
          skin REAL, sleep INTEGER, spo2 INTEGER, q REAL,
          src INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS event (
          ts INTEGER NOT NULL, id INTEGER NOT NULL, body BLOB,
          PRIMARY KEY (ts, id)
        );
        CREATE TABLE IF NOT EXISTS day (
          date TEXT PRIMARY KEY, json TEXT NOT NULL, updated INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS activity (
          id TEXT PRIMARY KEY, start INTEGER NOT NULL, json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS activity_start ON activity(start);
        """)
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let db else { return nil }
        var st: OpaquePointer?
        return sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK ? st : nil
    }

    // MARK: - Samples

    enum SampleSource: Int { case history = 0, live = 1 }

    /// Persist samples in ONE transaction and return only once it is durable.
    /// History replaces whatever was stored for a second; live samples never overwrite history.
    @discardableResult
    func insertSamples(_ samples: [HistorySample], source: SampleSource = .history) -> Bool {
        guard !samples.isEmpty else { return true }
        return queue.sync { () -> Bool in
            guard db != nil else { return false }
            let verb = source == .history ? "INSERT OR REPLACE" : "INSERT OR IGNORE"
            guard let st = prepare("""
                \(verb) INTO sample (ts,hr,rrn,rr0,rr1,rr2,rr3,gx,gy,gz,dyn,steps,cadence,act,skin,sleep,spo2,q,src)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """) else { return false }
            defer { sqlite3_finalize(st) }
            exec("BEGIN IMMEDIATE;")
            var ok = true
            for s in samples {
                sqlite3_reset(st)
                sqlite3_bind_int64(st, 1, Int64(s.ts))
                sqlite3_bind_int(st, 2, Int32(s.hr))
                sqlite3_bind_int(st, 3, Int32(s.rrCount))
                bindInt(st, 4, s.rrCount > 0 ? Int(s.rr0) : nil)
                bindInt(st, 5, s.rrCount > 1 ? Int(s.rr1) : nil)
                bindInt(st, 6, s.rrCount > 2 ? Int(s.rr2) : nil)
                bindInt(st, 7, s.rrCount > 3 ? Int(s.rr3) : nil)
                bindReal(st, 8, s.gx)
                bindReal(st, 9, s.gy)
                bindReal(st, 10, s.gz)
                bindReal(st, 11, s.dynAccel)
                bindInt(st, 12, s.stepCounter >= 0 ? Int(s.stepCounter) : nil)
                bindInt(st, 13, s.cadence >= 0 ? Int(s.cadence) : nil)
                bindInt(st, 14, s.activityClass >= 0 ? Int(s.activityClass) : nil)
                bindReal(st, 15, s.skinTemp)
                bindInt(st, 16, s.sleepState >= 0 ? Int(s.sleepState) : nil)
                bindInt(st, 17, s.spo2Raw >= 0 ? Int(s.spo2Raw) : nil)
                bindReal(st, 18, s.quality)
                sqlite3_bind_int(st, 19, Int32(source.rawValue))
                if sqlite3_step(st) != SQLITE_DONE { ok = false }
            }
            ok = exec(ok ? "COMMIT;" : "ROLLBACK;") && ok
            return ok
        }
    }

    private func bindInt(_ st: OpaquePointer, _ i: Int32, _ v: Int?) {
        if let v { sqlite3_bind_int64(st, i, Int64(v)) } else { sqlite3_bind_null(st, i) }
    }

    private func bindReal(_ st: OpaquePointer, _ i: Int32, _ v: Float) {
        if v.isNaN { sqlite3_bind_null(st, i) } else { sqlite3_bind_double(st, i, Double(v)) }
    }

    func samples(from: Int, to: Int) -> [HistorySample] {
        queue.sync {
            guard let st = prepare("""
                SELECT ts,hr,rrn,rr0,rr1,rr2,rr3,gx,gy,gz,dyn,steps,cadence,act,skin,sleep,spo2,q
                FROM sample WHERE ts >= ? AND ts < ? ORDER BY ts
                """) else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_int64(st, 1, Int64(from))
            sqlite3_bind_int64(st, 2, Int64(to))
            var out: [HistorySample] = []
            out.reserveCapacity(max(0, min(to - from, 200_000)))
            func real(_ c: Int32) -> Float {
                sqlite3_column_type(st, c) == SQLITE_NULL ? .nan : Float(sqlite3_column_double(st, c))
            }
            func int(_ c: Int32) -> Int? {
                sqlite3_column_type(st, c) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(st, c))
            }
            while sqlite3_step(st) == SQLITE_ROW {
                var s = HistorySample(ts: Int(sqlite3_column_int64(st, 0)), hr: UInt8(clamping: sqlite3_column_int(st, 1)))
                let n = Int(sqlite3_column_int(st, 2))
                var rr: [Int] = []
                for k in 0..<min(n, 4) { if let v = int(3 + Int32(k)) { rr.append(v) } }
                s.setRR(rr)
                s.gx = real(7); s.gy = real(8); s.gz = real(9); s.dynAccel = real(10)
                s.stepCounter = int(11).map { Int32($0) } ?? -1
                s.cadence = int(12).map { Int16(clamping: $0) } ?? -1
                s.activityClass = int(13).map { Int8(clamping: $0) } ?? -1
                s.skinTemp = real(14)
                s.sleepState = int(15).map { Int8(clamping: $0) } ?? -1
                s.spo2Raw = int(16).map { Int16(clamping: $0) } ?? -1
                s.quality = real(17)
                out.append(s)
            }
            return out
        }
    }

    /// (oldest ts, newest ts, count) of stored samples.
    func sampleStats() -> (oldest: Int?, newest: Int?, count: Int) {
        queue.sync {
            guard let st = prepare("SELECT MIN(ts), MAX(ts), COUNT(*) FROM sample") else { return (nil, nil, 0) }
            defer { sqlite3_finalize(st) }
            guard sqlite3_step(st) == SQLITE_ROW else { return (nil, nil, 0) }
            let a = sqlite3_column_type(st, 0) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(st, 0))
            let b = sqlite3_column_type(st, 1) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(st, 1))
            return (a, b, Int(sqlite3_column_int64(st, 2)))
        }
    }

    /// Newest second that came from the strap's history (not the live stream).
    func newestHistoryTs() -> Int? {
        queue.sync {
            guard let st = prepare("SELECT MAX(ts) FROM sample WHERE src = 0") else { return nil }
            defer { sqlite3_finalize(st) }
            guard sqlite3_step(st) == SQLITE_ROW, sqlite3_column_type(st, 0) != SQLITE_NULL else { return nil }
            return Int(sqlite3_column_int64(st, 0))
        }
    }

    /// Per-minute HR samples over a range (for the live/today charts).
    func minuteHR(from: Int, to: Int) -> [(ts: Int, bpm: Double)] {
        queue.sync {
            guard let st = prepare("""
                SELECT (ts/60)*60 AS m, AVG(hr) FROM sample WHERE ts >= ? AND ts < ? AND hr > 0 GROUP BY m ORDER BY m
                """) else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_int64(st, 1, Int64(from))
            sqlite3_bind_int64(st, 2, Int64(to))
            var out: [(Int, Double)] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append((Int(sqlite3_column_int64(st, 0)), sqlite3_column_double(st, 1)))
            }
            return out
        }
    }

    // MARK: - Events

    func insertEvents(_ events: [StoredEvent]) {
        guard !events.isEmpty else { return }
        queue.sync {
            guard let st = prepare("INSERT OR REPLACE INTO event (ts,id,body) VALUES (?,?,?)") else { return }
            defer { sqlite3_finalize(st) }
            exec("BEGIN;")
            for e in events {
                sqlite3_reset(st)
                sqlite3_bind_int64(st, 1, Int64(e.ts))
                sqlite3_bind_int(st, 2, Int32(e.id))
                _ = e.body.withUnsafeBytes { p in
                    sqlite3_bind_blob(st, 3, p.baseAddress, Int32(e.body.count), SQLITE_TRANSIENT)
                }
                sqlite3_step(st)
            }
            exec("COMMIT;")
        }
    }

    // MARK: - Days

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func saveDay(_ d: DayMetrics) {
        guard let data = try? encoder.encode(d), let json = String(data: data, encoding: .utf8) else { return }
        queue.sync {
            guard let st = prepare("INSERT OR REPLACE INTO day (date,json,updated) VALUES (?,?,?)") else { return }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, d.date, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 2, json, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 3, Int64(Date().timeIntervalSince1970))
            sqlite3_step(st)
        }
    }

    func days(from: String, to: String) -> [DayMetrics] {
        queue.sync {
            guard let st = prepare("SELECT json FROM day WHERE date >= ? AND date <= ? ORDER BY date") else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, from, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 2, to, -1, SQLITE_TRANSIENT)
            var out: [DayMetrics] = []
            while sqlite3_step(st) == SQLITE_ROW {
                guard let c = sqlite3_column_text(st, 0) else { continue }
                let s = String(cString: c)
                if let d = try? decoder.decode(DayMetrics.self, from: Data(s.utf8)) { out.append(d) }
            }
            return out
        }
    }

    func allDays() -> [DayMetrics] { days(from: "0000-00-00", to: "9999-99-99") }

    // MARK: - Activities (manual / live)

    func saveActivity(_ a: ActivityRecord) {
        guard let data = try? encoder.encode(a), let json = String(data: data, encoding: .utf8) else { return }
        queue.sync {
            guard let st = prepare("INSERT OR REPLACE INTO activity (id,start,json) VALUES (?,?,?)") else { return }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, a.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 2, Int64(a.start))
            sqlite3_bind_text(st, 3, json, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
        }
    }

    func deleteActivity(id: String) {
        queue.sync {
            guard let st = prepare("DELETE FROM activity WHERE id = ?") else { return }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
        }
    }

    func activities(from: Int, to: Int) -> [ActivityRecord] {
        queue.sync {
            guard let st = prepare("SELECT json FROM activity WHERE start >= ? AND start < ? ORDER BY start") else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_int64(st, 1, Int64(from))
            sqlite3_bind_int64(st, 2, Int64(to))
            var out: [ActivityRecord] = []
            while sqlite3_step(st) == SQLITE_ROW {
                guard let c = sqlite3_column_text(st, 0) else { continue }
                if let a = try? decoder.decode(ActivityRecord.self, from: Data(String(cString: c).utf8)) { out.append(a) }
            }
            return out
        }
    }

    // MARK: - Maintenance

    /// Delete raw seconds older than `days` (derived day results are kept forever).
    func pruneSamples(olderThanDays days: Int) {
        let cutoff = Int(Date().timeIntervalSince1970) - days * 86400
        queue.sync {
            guard let st = prepare("DELETE FROM sample WHERE ts < ?") else { return }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_int64(st, 1, Int64(cutoff))
            sqlite3_step(st)
        }
    }

    func wipeAll() {
        queue.sync {
            exec("DELETE FROM sample; DELETE FROM event; DELETE FROM day; DELETE FROM activity;")
            exec("VACUUM;")
        }
    }

    /// Size of the database file in bytes.
    var fileSize: Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
