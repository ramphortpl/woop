import Foundation
import Compression

/// Minimal .zip reader (stored + deflate entries, no ZIP64) — enough to open the WHOOP data
/// export straight from Mail/Files without unzipping it first.
enum ZipReader {
    struct Entry {
        let name: String
        let data: Data
    }

    static func entries(_ zip: Data) -> [Entry] {
        let b = [UInt8](zip)
        func u16(_ o: Int) -> Int { o + 2 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 4 <= b.count ? u16(o) | u16(o + 2) << 16 : 0 }

        // End of central directory: scan backwards (the comment can be up to 64 KiB).
        var eocd = -1
        var i = b.count - 22
        let stop = max(0, b.count - 22 - 65_536)
        while i >= stop {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return [] }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var out: [Entry] = []
        for _ in 0..<count {
            guard u32(p) == 0x0201_4B50 else { break }
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let usize = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let local = u32(p + 42)
            let nameBytes = Array(b[min(b.count, p + 46)..<min(b.count, p + 46 + nlen)])
            let name = String(decoding: nameBytes, as: UTF8.self)
            p += 46 + nlen + elen + clen
            guard u32(local) == 0x0403_4B50, !name.hasSuffix("/") else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start >= 0, start + csize <= b.count else { continue }
            let raw = Data(b[start..<(start + csize)])
            switch method {
            case 0:
                out.append(Entry(name: name, data: raw))
            case 8:
                if let d = inflate(raw, size: usize) { out.append(Entry(name: name, data: d)) }
            default:
                continue
            }
        }
        return out
    }

    /// Raw DEFLATE (RFC 1951) — what Apple's COMPRESSION_ZLIB decodes.
    private static func inflate(_ data: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, size, s, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        out.count = written
        return out
    }
}
