import Foundation

/// Minimal .zip reader (stored + deflate, data descriptors, ZIP64 sizes), pure Swift.
/// Reads the central directory; if it is missing (truncated download) it walks the local
/// headers instead.
enum ZipArchive {
    struct Entry: Equatable {
        var name: String
        var method: Int
        var flags: Int
        var crc: UInt32
        var compressedSize: Int
        var size: Int
        var localOffset: Int
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    struct File {
        var name: String
        var bytes: [UInt8]
    }

    enum Failure: Error, Equatable {
        case notAZip
        case unsupportedMethod(Int)
        case encrypted
        case corrupt(String)
        case crcMismatch(String)
    }

    static func isZip(_ b: [UInt8]) -> Bool {
        b.count >= 4 && b[0] == 0x50 && b[1] == 0x4B && ((b[2] == 3 && b[3] == 4) || (b[2] == 5 && b[3] == 6) || (b[2] == 7 && b[3] == 8))
    }

    /// Every regular file of the archive (entries that fail to decode are reported, not fatal).
    static func files(_ b: [UInt8]) -> (files: [File], errors: [String]) {
        var out: [File] = []
        var errors: [String] = []
        for e in entries(b) where !e.isDirectory {
            do {
                out.append(File(name: e.name, bytes: try extract(b, e)))
            } catch {
                errors.append("\(e.name) : \(error)")
            }
        }
        return (out, errors)
    }

    // MARK: Directory

    static func entries(_ b: [UInt8]) -> [Entry] {
        if let central = centralEntries(b), !central.isEmpty { return central }
        return localScan(b)
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> Int { o >= 0 && o + 2 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
    private static func u32(_ b: [UInt8], _ o: Int) -> Int { u16(b, o) | u16(b, o + 2) << 16 }
    private static func u64(_ b: [UInt8], _ o: Int) -> Int { u32(b, o) | u32(b, o + 4) << 32 }

    private static func name(_ bytes: ArraySlice<UInt8>) -> String {
        String(bytes: bytes, encoding: .utf8) ?? String(decoding: bytes.map { $0 }, as: UTF8.self)
    }

    private static func centralEntries(_ b: [UInt8]) -> [Entry]? {
        guard b.count >= 22 else { return nil }
        var eocd = -1
        var i = b.count - 22
        let stop = max(0, b.count - 22 - 65_557)
        while i >= stop {
            if b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 5 && b[i + 3] == 6 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        var count = u16(b, eocd + 10)
        var cdOffset = u32(b, eocd + 16)
        // ZIP64 end-of-central-directory (locator sits right before the classic record).
        if count == 0xFFFF || cdOffset == 0xFFFF_FFFF, eocd >= 20, u32(b, eocd - 20) == 0x0706_4B50 {
            let rec = u64(b, eocd - 20 + 8)
            if u32(b, rec) == 0x0606_4B50 {
                count = u64(b, rec + 32)
                cdOffset = u64(b, rec + 48)
            }
        }
        var p = cdOffset
        var out: [Entry] = []
        for _ in 0..<min(count, 100_000) {
            guard p + 46 <= b.count, u32(b, p) == 0x0201_4B50 else { break }
            let flags = u16(b, p + 8)
            let method = u16(b, p + 10)
            let crc = UInt32(truncatingIfNeeded: u32(b, p + 16))
            var csize = u32(b, p + 20)
            var usize = u32(b, p + 24)
            let nlen = u16(b, p + 28), elen = u16(b, p + 30), clen = u16(b, p + 32)
            var local = u32(b, p + 42)
            let nameStart = p + 46
            guard nameStart + nlen <= b.count else { break }
            let n = name(b[nameStart..<(nameStart + nlen)])
            // ZIP64 extra field: 8-byte values for the 32-bit fields that are saturated.
            var x = nameStart + nlen
            let xEnd = min(b.count, x + elen)
            while x + 4 <= xEnd {
                let id = u16(b, x), size = u16(b, x + 2)
                if id == 0x0001 {
                    var q = x + 4
                    if usize == 0xFFFF_FFFF { usize = u64(b, q); q += 8 }
                    if csize == 0xFFFF_FFFF { csize = u64(b, q); q += 8 }
                    if local == 0xFFFF_FFFF { local = u64(b, q) }
                }
                x += 4 + size
            }
            out.append(Entry(name: n, method: method, flags: flags, crc: crc, compressedSize: csize, size: usize, localOffset: local))
            p = nameStart + nlen + elen + clen
        }
        return out
    }

    /// Walk local file headers from the start (no central directory).
    private static func localScan(_ b: [UInt8]) -> [Entry] {
        var out: [Entry] = []
        var p = 0
        while p + 30 <= b.count, u32(b, p) == 0x0403_4B50 {
            let flags = u16(b, p + 6)
            let method = u16(b, p + 8)
            let crc = UInt32(truncatingIfNeeded: u32(b, p + 14))
            var csize = u32(b, p + 18)
            var usize = u32(b, p + 22)
            let nlen = u16(b, p + 26), elen = u16(b, p + 28)
            let dataStart = p + 30 + nlen + elen
            guard dataStart <= b.count else { break }
            let n = name(b[(p + 30)..<(p + 30 + nlen)])
            var entryCRC = crc
            if flags & 0x08 != 0 && csize == 0 {
                // Sizes follow the data: find the end of the deflate stream by decoding it.
                guard method == 8, let r = try? Inflate.inflate(Array(b[dataStart...])) else { break }
                csize = r.consumed
                usize = r.output.count
                var d = dataStart + csize
                if u32(b, d) == 0x0807_4B50 { d += 4 }
                entryCRC = UInt32(truncatingIfNeeded: u32(b, d))
            }
            out.append(Entry(name: n, method: method, flags: flags, crc: entryCRC, compressedSize: csize, size: usize, localOffset: p))
            var next = dataStart + csize
            if flags & 0x08 != 0 {
                if u32(b, next) == 0x0807_4B50 { next += 4 }
                next += 12
            }
            guard next > p else { break }
            p = next
        }
        return out
    }

    // MARK: Extraction

    static func extract(_ b: [UInt8], _ e: Entry) throws -> [UInt8] {
        guard e.flags & 0x01 == 0 else { throw Failure.encrypted }
        let p = e.localOffset
        guard p >= 0, p + 30 <= b.count, u32(b, p) == 0x0403_4B50 else { throw Failure.corrupt(e.name) }
        let start = p + 30 + u16(b, p + 26) + u16(b, p + 28)
        guard start <= b.count else { throw Failure.corrupt(e.name) }
        let end = min(b.count, start + e.compressedSize)
        let raw = Array(b[start..<end])
        let data: [UInt8]
        switch e.method {
        case 0:
            guard raw.count == e.compressedSize else { throw Failure.corrupt(e.name) }
            data = raw
        case 8:
            do {
                data = try Inflate.inflate(raw, expectedSize: e.size).output
            } catch {
                throw Failure.corrupt(e.name)
            }
        default:
            throw Failure.unsupportedMethod(e.method)
        }
        if e.crc != 0 || !data.isEmpty, CRC.crc32(data) != e.crc { throw Failure.crcMismatch(e.name) }
        return data
    }
}
