import XCTest
@testable import WoopCore

final class ZipTests: XCTestCase {
    /// Same generator as Tools/make_zip_fixtures.py.
    static func sampleText(_ n: Int) -> [UInt8] {
        var lines = ["ts,hr,label"]
        var x = 12345
        let labels = ["repos", "course", "sommeil", "vélo", "tennis"]
        for i in 0..<n {
            x = (x &* 1_103_515_245 &+ 12345) % 2_147_483_648
            let hr = 50 + (x >> 16) % 120
            lines.append("\(1_780_000_000 + i),\(hr),\(labels[(x >> 8) % 5])")
        }
        return Array((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func bytes(_ b64: String) -> [UInt8] {
        [UInt8](Data(base64Encoded: b64.replacingOccurrences(of: "\n", with: ""))!)
    }

    func testInflateAllBlockKinds() throws {
        let text = Self.sampleText(400)
        XCTAssertEqual(text.count, ZipFixtures.textLength)
        XCTAssertEqual(CRC.crc32(text), ZipFixtures.textCRC)
        for (name, b64) in [("dynamic", ZipFixtures.dynamic), ("fast", ZipFixtures.fast),
                            ("fixed", ZipFixtures.fixed), ("rle", ZipFixtures.rle)] {
            let raw = Self.bytes(b64)
            let r = try Inflate.inflate(raw)
            XCTAssertEqual(r.output, text, name)
            XCTAssertEqual(r.consumed, raw.count, name)
        }
        let stored = try Inflate.inflate(Self.bytes(ZipFixtures.stored))
        XCTAssertEqual(stored.output, Array(text.prefix(ZipFixtures.storedLength)))
    }

    func testInflateRejectsGarbage() {
        XCTAssertThrowsError(try Inflate.inflate([0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertThrowsError(try Inflate.inflate(Array(Self.bytes(ZipFixtures.dynamic).prefix(100))))
    }

    func testZipArchiveReadsWhoopExport() {
        let zip = Self.bytes(ZipFixtures.zipA)
        XCTAssertTrue(ZipArchive.isZip(zip))
        let r = ZipArchive.files(zip)
        XCTAssertEqual(r.errors, [])
        let names = r.files.map(\.name)
        XCTAssertTrue(names.contains("my_whoop_data_2026_11_08/physiological_cycles.csv"))
        XCTAssertTrue(names.contains("my_whoop_data_2026_11_08/journal_entries.csv"))
        let collected = WhoopExport.collect([ZipArchive.File(name: "my_whoop_data.zip", bytes: zip)])
        XCTAssertEqual(Set(collected.texts.map(\.name)), ["physiological_cycles.csv", "workouts.csv", "sleeps.csv", "journal_entries.csv"])
        let result = WhoopExport.importFiles(collected.texts)
        XCTAssertEqual(result.cycles, 2)
        XCTAssertEqual(result.workouts, 3)
        XCTAssertEqual(result.sleeps, 1)
        XCTAssertEqual(result.days.first { $0.date == "2026-11-08" }?.recovery, 45)
        XCTAssertEqual(result.days.first { $0.date == "2026-11-08" }?.naps.count, 1)
        let kinds = Dictionary(result.files.map { ($0.name, $0.kind) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(kinds["journal_entries.csv"], .journal)
        XCTAssertEqual(kinds["workouts.csv"], .workouts)
    }

    func testStreamedZipWithDataDescriptors() {
        let zip = Self.bytes(ZipFixtures.zipStreamed)
        let r = ZipArchive.files(zip)
        XCTAssertEqual(r.errors, [])
        XCTAssertEqual(WhoopExport.collect([ZipArchive.File(name: "a.zip", bytes: zip)]).texts.count, 4)
    }

    func testZipWithoutCentralDirectory() {
        let zip = Self.bytes(ZipFixtures.zipNoCentral)
        let c = WhoopExport.collect([ZipArchive.File(name: "partiel.zip", bytes: zip)])
        XCTAssertEqual(Set(c.texts.map(\.name)), ["physiological_cycles.csv", "workouts.csv", "sleeps.csv", "journal_entries.csv"])
    }

    func testNestedZipAndExtensionlessDownload() {
        // A zip saved without its extension (e.g. a download) is still recognized by content.
        let zip = Self.bytes(ZipFixtures.zipNested)
        let c = WhoopExport.collect([ZipArchive.File(name: "telechargement", bytes: zip)])
        XCTAssertEqual(c.texts.count, 4)
        XCTAssertEqual(WhoopExport.importFiles(c.texts).cycles, 2)
    }

    func testSemicolonCSVAndDates() {
        let csv = "Heure de début du cycle;Heure de fin du cycle;Fuseau horaire du cycle;Score de récupération %;Effort du jour\n08/11/2026 02:31;;UTC+01:00;45;12,8\n"
        let r = WhoopExport.importFiles([WhoopExport.NamedText(name: "cycles.csv", text: csv)])
        XCTAssertEqual(r.cycles, 1)
        XCTAssertEqual(r.days.first?.date, "2026-11-08")
        XCTAssertEqual(r.days.first?.strain, 12.8)
        XCTAssertEqual(WhoopExport.parseTime("2026-11-08T01:31:00Z", offsetMinutes: 60), WhoopExport.parseTime("2026-11-08 02:31:00", offsetMinutes: 60))
        XCTAssertEqual(WhoopExport.parseTime("2026-11-08 02:31:00.250+01:00", offsetMinutes: 0), WhoopExport.parseTime("2026-11-08 02:31:00", offsetMinutes: 60))
    }

    func testTextDecoding() {
        let latin1: [UInt8] = Array("Nom de l'activit".utf8) + [0xE9] + Array(",x,y\n".utf8)
        XCTAssertEqual(WhoopExport.decodeText(latin1), "Nom de l'activité,x,y\n")
        let utf16: [UInt8] = [0xFF, 0xFE] + Array("a,b,c".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        XCTAssertEqual(WhoopExport.decodeText(utf16), "a,b,c")
    }
}
